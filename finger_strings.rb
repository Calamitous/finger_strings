#!/usr/bin/env ruby

require 'json'
require 'readline'
require 'date'
# require 'pry-nav'; binding.pry

class Config
  @@todo_file = "#{ENV['HOME']}/.finger_strings"

  VERSION              = '0.0.2'
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
  MIN_WIDTH = 80
  WIDTH = [ENV['COLUMNS'].to_i, `tput cols`.chomp.to_i, MIN_WIDTH].compact.max

  def self.say(*stuff)
    stuff = stuff.join(' ') if stuff.is_a? Array
    puts stuff.colorize
  end

  def self.flowerbox(*lines, box_character: '*', box_thickness: 1)
    box_thickness.times do say box_character * WIDTH end
    lines.each { |line| say line }
    box_thickness.times do say box_character * WIDTH end
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

  def untag()
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
    self.load_todos.select { |todo| todo.category == 'done' }
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
      'someday' => [],
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

    location_index = todos.index { |todo| todo.index == self.index }
    todos[location_index] = self

    Todo.save_todos(todos)
  end

  def delete
    todos = Todo.load_todos

    location_index = todos.index { |todo| todo.index == self.index }
    todos.delete_at(location_index)

    Todo.save_todos(todos)
  end

  def prioritize
    todos = Todo.load_todos

    location_index = todos.index { |todo| todo.index == self.index }
    todos.delete_at(location_index)
    todos.unshift(self)

    Todo.save_todos(todos)
  end

  def upcoming?
    self.category == 'upcoming'
  end

  def available?
    available_on.nil? || Date.today >= available_on
  end

  def schedule(date)
    todos = Todo.load_todos

    location_index = todos.index { |todo| todo.index == self.index }
    todos[location_index].available_on = date
    todos[location_index].category = 'upcoming'

    Todo.save_todos(todos)
  end

  def recur(days)
    todos = Todo.load_todos

    location_index = todos.index { |todo| todo.index == self.index }
    todos[location_index].recurrence_rule = days

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
end

class Date
  def tomorrow?
    self == Date.today.next
  end

  def this_week?
    self < Date.today + 7
  end

  def next_week?
    self >= Date.today + 7 && self < Date.today + 14
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

  def decolorize
    self.
      gsub(/\\{/, '|KOPEN|').
      gsub(/\\}/, '|KCLOSE|').
      gsub(/{[rgybmcwniuv]+\s|}/, '').
      gsub(/\|KOPEN\|/, '{').
      gsub(/\|KCLOSE\|/, '}')
  end

  def wrapped(width = Display::WIDTH)
    self.gsub(/.{1,#{width}}(?:\s|\Z|\-)/) {
      ($& + 5.chr).gsub(/\n\005/,"\n").gsub(/\005/,"\n")
    }
  end

  def color_bounded
    COLOR_RESET + self.gsub(/\n/, "\n#{COLOR_RESET}") + COLOR_RESET
  end
end

class StartUpper
  CMD_MAP = {
    'a'          => 'add',
    'add'        => 'add',
    'c'          => 'complete',
    'complete'   => 'complete',
    'l'          => 'list',
    'list'       => 'list',
    'd'          => 'delete',
    'delete'     => 'delete',
    'p'          => 'priority',
    'prioritize' => 'priority',
    'r'          => 'recur',
    'recur'      => 'recur',
    's'          => 'schedule',
    'schedule'   => 'schedule',
    'h'          => 'help',
    'tag'        => 'tag',
    't'          => 'tag',
    'untag'      => 'untag',
    '?'          => 'help',
    'help'       => 'help',
    'q'          => 'quit',
    'quit'       => 'quit',
    'clear'      => 'clear',
    'i'          => 'info',
    'info  '     => 'info',
    'cal'        => 'calendar',
    'calendar'   => 'calendar',
  }

  CATEGORY_COLORS = {
    'today' => '{wi ',
    'upcoming' => '{w ',
    'someday' => '{w ',
    'recurring' => '{w ',
    'done' => '{wv '
  }

  def handle(line)
    tokens = line.split(/\s/)
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

  def show_today()
    clear
    show('today', Todo.today)
  end

  def show_done()
    clear
    show('done', Todo.done)
  end

  def show_upcoming
    clear
    upcoming_hash = Todo.upcoming
    upcoming_hash.keys.sort.each do |date|
      follower = "(#{date.strftime('%A')})" if date.this_week?
      follower = "(Next #{date.strftime('%A')})" if date.next_week?
      follower = '(Tomorrow)' if date.tomorrow?

      Display.say("{bi #{date.to_s}} {wi #{follower}}")

      upcoming_hash[date].each { |todo| Display.say("    #{todo.to_string}") }
    end
  end

  def show_tags
    clear
    tags_hash = Todo.tag_hash
    tags_hash.keys.sort.each do |tag|
      Display.say("{gi #{tag}}")
      tags_hash[tag].each do |todo|
        Display.say("    #{todo.to_string}")
      end
    end
  end

  def show(category, todos)
    if category == 'today'
      Display.say("#{CATEGORY_COLORS[category]} #{category.titleize} (#{Date.today.to_s}) }")
    else
      Display.say(CATEGORY_COLORS[category] + category.titleize + '}')
    end

    if todos.size == 0
      Display.say('{r (none)}')
    else
      todos.each do |todo|
        Display.say(todo.to_string)
      end
    end
  end

  def show_all()
    clear

    Todo.by_category.each do |category, todos|
      Display.say()
      show(category, todos)
    end
  end

  def add(*args)
    Todo.create('text' => args.join(' '))
    list
  end

  def list(*args)
    args.flatten!

    return show_all if args       == ['all']       || args == ['*']
    return show_done if args      == ['done']      || args == ['d']
    return show_upcoming if args  == ['upcoming']  || args == ['u']
    return show_recurring if args == ['recurring'] || args == ['r']
    return show_tags if args      == ['tags']      || args == ['t']
    show_today
  end

  def clear(*_args)
    Display.say `tput reset`.chomp
  end

  def complete(*args)
    args.flatten!

    return print_argument_error unless args.size == 1

    id = args[0]

    return print_lookup_error(id) unless todo = Todo.find(id)

    todo.mark_done
    list
  end

  def priority(*args)
    args.flatten!

    return print_argument_error unless args.size == 1

    id = args[0]

    return print_lookup_error(id) unless todo = Todo.find(id)

    todo.prioritize
    list
  end

  def schedule(args)
    args.flatten!

    return print_argument_error unless args.size == 2

    id = args[0]
    date = args[1]

    return print_lookup_error(id) unless todo = Todo.find(id)

    unless to_date = Date.parse(date)
      Display.say("I couldn't understand your date '#{date}' (should be YYYY-MM-dd)")
      return
    end

    unless to_date > Date.today
      Display.say("Schedules Todos should happen in the future.  #{date} is not in the future.")
      return
    end

    todo.schedule(to_date)
    list
  end

  def tag(args)
    args.flatten!

    return print_argument_error unless args.size == 2

    id = args[0]
    tag = args[1]

    return print_lookup_error(id) unless todo = Todo.find(id)

    todo.add_tag(tag)
    list
  end

  def untag(args)
    args.flatten!

    return print_argument_error unless args.size == 1

    id = args[0]
    tag = args[1]

    return print_lookup_error(id) unless todo = Todo.find(id)

    todo.untag
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

  def delete(args)
    args.flatten!

    return print_argument_error if args.size != 1

    id = args[0]

    return print_lookup_error(id) unless todo = Todo.find(id)

    todo.delete
    list
  end

  def print_argument_error
    Display.say("I don't understand what you want to do")
  end

  def print_lookup_error(id)
    Display.say("I couldn't find a todo with an ID of #{id}")
  end

  # TODO
  def undo
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
      '{wu c}omplete                   - Mark a Todo as done',
      '{wu p}rioritize                 - Move a Todo to the top of the list',
      '{w t}ag <id> <tag>              - Add Tag to a Todo',
      '{wu s}chedule <id> <YYYY-MM-DD> - Schedule a Todo for a future date',
      '{wu r}ecur <id> <amount>        - Set a recurrence rule for a Todo',
      'untag <id>                      - Remove all Tags from a Todo',
      '{wu d}elete                     - Delete a Todo entirely',
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

    Display.say "Welcome to FingerStrings v#{Config::VERSION}.  Type 'help' for a list of commands; Ctrl-D or 'quit' to leave."
    show_today

    while line = readline("~> ") do
      handle(line)
    end
  end
end

StartUpper.new
