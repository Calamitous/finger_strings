#!/usr/bin/env ruby

require 'json'
require 'readline'
require 'date'

# Only for debugging
# require 'pry-nav'; binding.pry

class Config
  @@todo_file = $test_todo_file || "#{ENV['HOME']}/.finger_strings"

  VERSION              = '0.0.3'
  HISTORY_FILE         = "#{ENV['HOME']}/.finger_strings.history"
  EMPTY_TODOS          = []
  FINGERSTRINGS_SCRIPT = __FILE__

  def self.todo_file=(filepath)
    @@todo_file = filepath
  end

  def self.todo_file
    @@todo_file
  end
end

class Display
  @@marker = nil
  MIN_WIDTH = 80

  def self.line_say(*stuff)
    stuff = stuff.join(' ') if stuff.is_a? Array
    stuff = stuff.gsub(/(\|.*)$/, '{ig \1}')
    stuff = stuff.gsub(/(\|.*)\W/, '{ig \1}')
    puts stuff.colorize
  end

  def self.say(*stuff)
    stuff = stuff.join(' ') if stuff.is_a? Array
    puts stuff.colorize
  end

  def self.mark
    mark = '-' * width
    self.say(mark)
  end

  def self.size_changed
    StartUpper.show_today
  end

  def self.clear
    say `tput reset`.chomp
  end

  def self.width
    [ENV['COLUMNS'].to_i, `tput cols`.chomp.to_i, MIN_WIDTH].compact.max
  end

  def self.flowerbox(*lines, box_character: '*', box_thickness: 1)
    box_thickness.times do say box_character * width end
    lines.each { |line| say line }
    box_thickness.times do say box_character * width end
  end

  def self.add_marker(index)
    @@marker = index
  end

  def self.marker
    @@marker
  end
end

class Hash
  def to_todo
    Todo.new(self)
  end
end

class Todo
  attr_accessor :index, :category, :text, :completed_at, :available_on, :recurrence_rule #, :due_on

  def initialize(data_hash)
    @text = data_hash['text']
    @category = data_hash['category'] || 'today'
    @completed_at = data_hash['completed_at']
    @available_on = data_hash['available_on']
    @recurrence_rule = data_hash['recurrence_rule']
  end

  def to_string
    display = "#{index}. #{text}"
    display += " {wi Recurs #{recurrence_rule} days after completion}" if recurrence_rule
    display += " {c Completed #{DateTime.parse(completed_at).strftime('%Y-%m-%d')}}" if category == 'done'
    display
  end

  def self.load_todos
    unless File.exists? Config.todo_file
      puts "TODO file not found, building..."
      File.umask(0122)
      File.open(Config.todo_file, 'w') { |f| f.write(Config::EMPTY_TODOS.to_json) }
    end

    begin
      todos = JSON.parse(File.read(Config.todo_file)).map(&:to_todo)
      todos.map! { |todo| todo.available_on = Date.parse(todo.available_on) unless todo.available_on.nil?; todo }
      # todos.map! { |todo| todo.due_on = Date.parse(todo.due_on) unless todo.due_on.nil? }
      self.index_todos(todos)
    rescue JSON::ParserError => e
      puts "Your read file appears to be corrupt.  Could not parse valid JSON from #{Config.todo_file} Please fix or delete this read file."
      exit(1)
    end
  end

  def self.save_todos(todos)
    File.write(Config.todo_file, todos.map(&:to_hash).to_json)
  end

  def self.index_todos(todos)
    todos.each_with_index do |todo, idx|
      todo.index = idx.to_s
    end

    todos
  end

  def add_tag(new_tag)
    new_tag = '|' + new_tag unless new_tag[0] == '|'

    @text += " #{new_tag}"

    todos = Todo.load_todos

    location_index = todos.index { |todo| todo.index == self.index }
    todos[location_index] = self

    Todo.save_todos(todos)
  end

  def untag
    @text = text.split(' ').reject{ |word| word[0] == '|' }.join(' ')

    todos = Todo.load_todos

    location_index = todos.index { |todo| todo.index == self.index }
    todos[location_index] = self

    Todo.save_todos(todos)
  end

  def tags
    text.split.select{ |word| word[0] == '|' }
  end

  def self.today
    self.load_todos.select { |todo| todo.category == 'today' }
  end

  def self.done
    self.load_todos.select { |todo| todo.category == 'done' }.sort { |left, right| right.completed_at <=> left.completed_at }
  end

  def self.backlog
    self.load_todos.select { |todo| todo.category == 'backlog' }
  end

  def self.not_done
    self.load_todos.select { |todo| todo.category != 'done' }
  end

  def self.upcoming
    self.load_todos.select { |todo| todo.category == 'upcoming' }.group_by(&:available_on)
  end

  def self.tagged
    self.not_done.select { |todo| todo.tags.any? }
  end

  def self.find_all_by_tag(tag)
    self.tagged.select do |todo|
      todo.tags.include?(tag)
    end
  end

  def self.tag_hash
    tag_hash = {}
    self.all_tags.each do |tag|
      tag_hash[tag] = find_all_by_tag(tag)
    end
    tag_hash
  end

  def self.all_tags
    self.tagged.map(&:tags).flatten.uniq.sort
  end

  def self.by_category
    todos = {
      'today' => [],
      'upcoming' => [],
      'backlog' => [],
      'recurring' => [],
      'done' => []
    }

    self.load_todos.each { |todo| todos[todo.category] << todo }

    todos
  end

  def self.find(index)
    self.load_todos.detect { |todo| todo.index == index }
  end

  def self.create(data_hash)
    new_todo = self.new(data_hash)
    Todo.save_todos(self.load_todos << new_todo)
    new_todo
  end

  def to_hash
    hash = {'text' => text, 'category' => category}
    hash['completed_at'] = completed_at.to_s if completed_at
    hash['available_on'] = available_on.to_s if available_on
    hash['recurrence_rule'] = recurrence_rule.to_s if recurrence_rule
    hash
  end

  def mark_done
    @completed_at = Time.now

    unless recurrence_rule.nil?
      next_date = Date.today + Integer(recurrence_rule)
      return self.schedule(next_date)
    end

    @category = 'done'

    todos = Todo.load_todos

    original_todo_index = todos.map(&:index).index(self.index.to_s)

    todos[original_todo_index] = self

    if Display.marker && original_todo_index <= (Display.marker + 1)
      Display.add_marker(Display.marker - 1)
    end

    Todo.save_todos(todos)
  end

  def delete
    todos = Todo.load_todos

    original_todo_index = todos.map(&:index).index(self.index.to_s)

    todos.delete_at(original_todo_index)

    if Display.marker && original_todo_index <= (Display.marker + 1)
      Display.add_marker(Display.marker - 1)
    end

    Todo.save_todos(todos)
  end

  def deprioritize
    todos = Todo.load_todos

    original_todo_index = todos.map(&:index).index(self.index.to_s)

    todos.delete_at(original_todo_index)
    todos.push(self)

    if Display.marker && original_todo_index <= (Display.marker + 1)
      Display.add_marker(Display.marker - 1)
    end

    Todo.save_todos(todos)
  end

  def backlog
    todos = Todo.load_todos

    original_todo_index = todos.map(&:index).index(self.index.to_s)
    todos.delete_at(original_todo_index)
    todos.unshift(self)
    self.category = 'backlog'
    self.available_on = nil

    if Display.marker && (original_todo_index <= Display.marker)
      Display.add_marker(Display.marker - 1)
    end

    Todo.save_todos(todos)
  end

  def mark
    todos = Todo.today

    original_todo_index = todos.map(&:index).index(self.index.to_s)

    Display.add_marker original_todo_index
  end

  def prioritize
    todos = Todo.load_todos

    original_todo_index = todos.map(&:index).index(self.index.to_s)
    todos.delete_at(original_todo_index)
    todos.unshift(self)
    self.category = 'today'
    self.available_on = nil

    if Display.marker && (original_todo_index > Display.marker)
      Display.add_marker(Display.marker + 1)
    end

    Todo.save_todos(todos)
  end

  def upcoming?
    self.category == 'upcoming'
  end

  def available?
    available_on.nil? || Date.today >= available_on
  end

  def schedule(date)
    return self.prioritize if date == Date.today

    todos = Todo.load_todos

    original_todo_index = todos.map(&:index).index(self.index.to_s)

    todos[original_todo_index].available_on = date
    todos[original_todo_index].category = 'upcoming'

    if Display.marker && original_todo_index <= (Display.marker + 1)
      Display.add_marker(Display.marker - 1)
    end

    Todo.save_todos(todos)
  end

  def recur(days)
    todos = Todo.load_todos

    original_todo_index = todos.map(&:index).index(self.index.to_s)

    todos[original_todo_index].recurrence_rule = days

    Todo.save_todos(todos)
  end

  def self.update_for_schedules
    todos = Todo.load_todos

    todos.select(&:upcoming?).select(&:available?).each do |todo|
      todo.available_on = nil
      todo.category = 'today'
      todo.prioritize
    end
  end

  def defer
    self.schedule(Util.dow_to_date('mon'))
  end

  def long_defer
    self.schedule(Date.today + 30)
  end
end

class Date
  def tomorrow?
    self == Date.today.next
  end

  def this_week?
    self < Date.today + 6
  end

  def next_week?
    self >= Date.today + 6 && self < Date.today + 14
  end
end

class String
  COLOR_MAP = {
    'n' => '0',
    'i' => '1',
    'u' => '4',
    'v' => '7',
    'r' => '31',
    'g' => '32',
    'y' => '33',
    'b' => '34',
    'm' => '35',
    'c' => '36',
    'w' => '37',
  }

  COLOR_RESET = "\033[0m"

  def titleize
    self[0].upcase + self[1..-1]
  end

  def color_token
    if self !~ /\w/
      return { '\{' => '|KOPEN|', '\}' => '|KCLOSE|', '}' => COLOR_RESET}[self]
    end

    tag = self.scan(/\w/).map{ |t| COLOR_MAP[t] }.sort.join(';')
    "\033[#{tag}m"
  end

  def colorize
    r = /\\{|{[rgybmcwniuv]+\s|\\}|}/
    split = self.split(r, 2)

    return self.color_bounded if r.match(self).nil?
    newstr = split.first + $&.color_token + split.last

    if r.match(newstr).nil?
      return (newstr + COLOR_RESET).gsub(/\|KOPEN\|/, '{').gsub(/\|KCLOSE\|/, '}').color_bounded
    end

    newstr.colorize.color_bounded
  end

  def color_bounded
    COLOR_RESET + self.gsub(/\n/, "\n#{COLOR_RESET}") + COLOR_RESET
  end
end

class StartUpper
  CMD_MAP = {
    'a'            => 'add',
    'add'          => 'add',
    'b'            => 'backlog',
    'backlog'      => 'backlog',
    'c'            => 'complete',
    'complete'     => 'complete',
    'l'            => 'list',
    'list'         => 'list',
    'x'            => 'delete',
    'delete'       => 'delete',
    'd'            => 'defer',
    'dw'           => 'defer',
    'defer'        => 'defer',
    'dm'           => 'long_defer',
    'longdefer'    => 'long_defer',
    'p'            => 'prioritize',
    'prioritize'   => 'prioritize',
    '!'            => 'deprioritize',
    'deprioritize' => 'deprioritize',
    'r'            => 'recur',
    'recur'        => 'recur',
    's'            => 'schedule',
    'schedule'     => 'schedule',
    'h'            => 'help',
    'tag'          => 'tag',
    't'            => 'tag',
    'untag'        => 'untag',
    '?'            => 'help',
    'help'         => 'help',
    'q'            => 'quit',
    'quit'         => 'quit',
    'clear'        => 'clear',
    'i'            => 'info',
    'info  '       => 'info',
    'cal'          => 'calendar',
    'calendar'     => 'calendar',
    'm'            => 'mark',
    'mark'         => 'mark',
  }

  CATEGORY_COLORS = {
    'today' => '{wi ',
    'upcoming' => '{w ',
    'backlog' => '{r ',
    'recurring' => '{w ',
    'done' => '{wv '
  }

  def handle(line)
    tokens = line.strip.split(/\s+/)
    cmd = tokens.first
    if !CMD_MAP.include?(cmd)
      Display.say 'I didn\'t understand your command.  Type "help" for a list of valid commands.'
      return
    end
    args = tokens[1..-1]
    cmd = CMD_MAP[cmd] || cmd || 'list'
    return self.send(cmd.to_sym, args)
  end

  def calendar(_args)
    Display.say `cal -A 1 -B 1`.gsub(/_.(\d)/, '{bv \1}')
  end

  def quit(_args)
    exit(0)
  end

  def self.show_today
    Display.clear
    show('today', Todo.today)
  end

  def self.show_done
    Display.clear
    show('done', Todo.done)
  end

  def self.show_backlog
    Display.clear
    show('backlog', Todo.backlog)
  end

  def show_upcoming
    Display.clear
    upcoming_hash = Todo.upcoming
    upcoming_hash.keys.sort.each do |date|
      follower = "[#{date.strftime('%A')}]" if date.this_week?
      follower = "[Next #{date.strftime('%A')}]" if date.next_week?
      follower = '[Tomorrow]' if date.tomorrow?

      Display.say("{bi #{date.to_s}} {wi #{follower}}")

      upcoming_hash[date].each { |todo| Display.say("    #{todo.to_string}") }
    end
  end

  def show_tags
    Display.clear
    tags_hash = Todo.tag_hash
    tags_hash.keys.sort.each do |tag|
      Display.say("{gi #{tag}}")
      tags_hash[tag].each do |todo|
        Display.say("    #{todo.to_string}")
      end
    end
  end

  def self.show(category, todos)
    if category == 'today'
      Display.say("#{CATEGORY_COLORS[category]} Today (#{todos.size} items) [#{Date.today.to_s}] }")
    else
      Display.say(CATEGORY_COLORS[category] + category.titleize + '}')
    end

    if todos.size == 0
      Display.say('{r (none)}')
    else
      todos.each_with_index do |todo, raw_idx|
        Display.line_say(todo.to_string)
        Display.mark if Display.marker == raw_idx if category == 'today'
      end
    end
  end

  def show_all
    Display.clear

    Todo.by_category.each do |category, todos|
      Display.say
      StartUpper.show(category, todos)
    end
  end

  def add(*args)
    Todo.create('text' => args.join(' '))
    list
  end

  def list(*args)
    args.flatten!

    return show_all if args             == ['all']       || args == ['*']
    return StartUpper.show_done if args == ['done']      || args == ['d']
    return show_upcoming if args        == ['upcoming']  || args == ['u']
    return show_recurring if args       == ['recurring'] || args == ['r']
    return show_tags if args            == ['tags']      || args == ['t']
    return StartUpper.show_backlog if args         == ['backlog']   || args == ['b']
    StartUpper.show_today
  end

  def clear(*_args)
    Display.clear
  end

  def self.clear(*_args)
    Display.clear
  end

  def single_todo_command(*args)
    args.flatten!

    return print_argument_error unless args.size == 1

    return print_lookup_error(id) unless todo = Todo.find(args[0])

    yield todo

    list
  end

  def complete(*args)
    single_todo_command(args) { |todo| todo.mark_done }
  end

  def backlog(*args)
    single_todo_command(args) { |todo| todo.backlog }
  end

  def deprioritize(*args)
    single_todo_command(args) { |todo| todo.deprioritize }
  end

  def prioritize(*args)
    single_todo_command(args) { |todo| todo.prioritize }
  end

  def mark(*args)
    single_todo_command(args) { |todo| todo.mark }
  end

  def untag(args)
    single_todo_command(args) { |todo| todo.untag }
  end

  def delete(args)
    single_todo_command(args) { |todo| todo.delete }
  end

  def defer(args)
    single_todo_command(args) { |todo| todo.defer }
  end

  def long_defer(args)
    single_todo_command(args) { |todo| todo.long_defer }
  end

  def schedule(args)
    args.flatten!

    return print_argument_error unless [2, 3].include? args.size

    id = args[0]
    date_request = args[1..-1].join(' ')

    return print_lookup_error(id) unless todo = Todo.find(id)

    to_date = Util.specials_to_date(date_request) || Util.dow_to_date(date_request) || Util.days_to_date(date_request) || Util.parse_date(date_request)

    unless to_date
      Display.say("I couldn't understand your date '#{date_request}' (should be YYYY-MM-dd, or mon/tue/wed, etc.)")
      return
    end

    unless to_date >= Date.today
      Display.say("Schedules Todos should not happen in the past.  #{to_date} is in the past.")
      return
    end

    todo.schedule(to_date)
    list
  end

  def tag(args)
    args.flatten!

    return print_argument_error unless args.size == 2

    id = args[0]
    tag = args[1].downcase

    return print_lookup_error(id) unless todo = Todo.find(id)

    todo.add_tag(tag)
    list
  end

  def recur(args)
    args.flatten!

    return print_argument_error unless args.size == 2

    id = args[0]
    days = args[1]

    return print_lookup_error(id) unless todo = Todo.find(id)

    unless to_days = Integer(days)
      Display.say("I couldn't understand your amount '#{amount}' (should be an integer)")
      return
    end

    if to_days > 0
      Display.say("Todo is set to recur #{to_days} after completion.")
    else
      Display.say("Recurrence has been disabled for this Todo")
    end

    todo.recur(to_days)
    list
  end

  def print_argument_error
    Display.say("I don't understand what you want to do")
  end

  def print_lookup_error(id)
    Display.say("I couldn't find a todo with an ID of #{id}")
  end

  def info(*_args)
    stats = Todo.by_category.map { |category, todos| "#{todos.size} Todos in #{category}" }
    stats.unshift "FingerStrings v#{Config::VERSION}"

    Display.flowerbox(*stats, box_thickness: 0)
  end

  def help(*_args)
    Display.flowerbox(
      "FingerStrings v#{Config::VERSION}",
      '',
      'Commands (the starting letter can be used if underlined)',
      '========',
      '{wu a}dd <text>                 - Add a new Todo',
      '{wu l}ist                       - List today\'s Todos',
      '    l *, l all                  - List Todos in all categories',
      '    l {wu u}pcoming             - List Upcoming Todos',
      '    l {wu r}ecurring            - List Recurring Todos',
      '    l {wu t}ags                 - List Tags and tagged Todos',
      '{wu c}omplete <id>              - Mark a Todo as done',
      '{wu p}rioritize <id>            - Move a Todo to the top of the list',
      '!, deprioritize <id>            - Move a Todo to the bottom of the list',
      '{w t}ag <id> <tag>              - Add Tag to a Todo',
      '{wu s}chedule <id> <YYYY-MM-DD> - Schedule a Todo for a future date',
      '{wu r}ecur <id> <amount>        - Set a recurrence rule for a Todo',
      '{wu m}ark <id>                  - Add a marker below the specified todo (impermanent)',
      'untag <id>                      - Remove all Tags from a Todo',
      'delete <id>, x <id>             - Delete a Todo entirely',
      '{wu d}efer <id>, dw <id>        - Defer a Todo to the following Monday',
      'longdefer <id>, dm <id>         - Defer a Todo for 30 days',
      '{wu i}nfo                       - Display FingerStrings version and stats',
      '{wu h}elp, ?                    - Display this text',
      'clear                           - Clear screen',
      '',
      'Full documentation available here:',
      'https://github.com/Calamitous/finger_strings/blob/master/README.md',
      box_character: '')
  end

  def readline(prompt)
    if !@history_loaded && File.exist?(Config::HISTORY_FILE)
      @history_loaded = true
      if File.readable?(Config::HISTORY_FILE)
        File.readlines(Config::HISTORY_FILE).each { |l| Readline::HISTORY.push(l.chomp) }
      end
    end

    if line = Readline.readline(prompt, true)
      if File.writable?(Config::HISTORY_FILE)
        File.open(Config::HISTORY_FILE) { |f| f.write(line+"\n") }
      end
      return line
    else
      return nil
    end
  end

  def initialize
    if ARGV.include?('--help')
      Display.flowerbox(
        "FingerStrings v#{Config::VERSION}",
        '',
        'Options',
        '========',
        '--schedule-update:      Updates all the todos based on the current date',
        '--todo-file <filepath>: Loads the specified todo file instead of the default ~/.finger_strings',
        '',
        '  NOTE: This should be run with the following crontab:',
        "  1 0 * * * #{Config::FINGERSTRINGS_SCRIPT} --schedule-update"
      )
      exit(0)
    end

    if ARGV.include?('--todo-file')
      Config.todo_file = ARGV[ARGV.index('--todo-file') + 1]
    end

    if ARGV.include?('--schedule-update')
      Todo.update_for_schedules
      exit(0)
    end

    Signal.trap('SIGWINCH', :'Display.size_changed')

    Display.say "Welcome to FingerStrings v#{Config::VERSION}.  Type 'help' for a list of commands; Ctrl-D or 'quit' to leave."
    StartUpper.show_today

    while line = readline("~> ") do
      handle(line)
    end
  end
end

class Util
  def self.days_to_date(date_request)
    return nil unless date_request =~ /^\d+\s*days?$/
    days = date_request.split(/\s/).first.to_i
    Date.today + days
  end

  def self.parse_date(date_request)
    begin
      return Date.parse(date_request)
    rescue
    end

    nil
  end

  def self.specials_to_date(date_request)
    return Date.today + 1 if date_request.downcase == 'tomorrow'
    return Date.today if date_request.downcase == 'today'
    nil
  end

  def self.dow_to_date(date_request)
    dows = %w{sun mon tue wed thu fri sat}

    request_day = date_request.split(/\s+/).last
    request_dow = dows.index(request_day)

    return nil unless request_dow

    today_dow = Date.today.wday

    date_gap = request_dow - today_dow
    date_gap += 7 if date_gap <= 0
    next_date = Date.today + date_gap

    next_date += 7 if next_date <= Date.today

    # Allow "next" or "n" to be used to push a date out a week
    next_date += 7 if %w{next n}.include? date_request.split(/\s+/).first.downcase

    next_date
  end
end

StartUpper.new if __FILE__==$0
