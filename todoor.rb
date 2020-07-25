#!/usr/bin/env ruby

require 'json'
require 'readline'
require 'date'

class Config
  VERSION       = '0.0.1'
  TODO_FILE     = "#{ENV['HOME']}/.todoor"
  HISTORY_FILE  = "#{ENV['HOME']}/.todoor.history"
  EMPTY_TODOS   = []
  TODOOR_SCRIPT = __FILE__
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
  attr_accessor :index, :category, :text, :completed_at, :available_on # , :recurrence_rule, :due_on, :tags

  def initialize(data_hash)
    @text = data_hash['text']
    @category = data_hash['category'] || 'today'
    @completed_at = data_hash['completed_at']
    @available_on = data_hash['available_on']
  end

  def to_string
    return "#{index}. #{text} {bi (Available on #{available_on})}" if available_on

    "#{index}. #{text}"
  end

  def self.load_todos
    unless File.exists? Config::TODO_FILE
      puts "TODO file not found, building..."
      File.umask(0122)
      File.open(Config::TODO_FILE, 'w') { |f| f.write(Config::EMPTY_TODOS.to_json) }
    end

    begin
      todos = JSON.parse(File.read(Config::TODO_FILE)).map(&:to_todo)
      todos.map! { |todo| todo.available_on = Date.parse(todo.available_on) unless todo.available_on.nil?; todo }
      # todos.map! { |todo| todo.due_on = Date.parse(todo.due_on) unless todo.due_on.nil? }
      self.index_todos(todos)
    rescue JSON::ParserError => e
      puts "Your read file appears to be corrupt.  Could not parse valid JSON from #{Config::TODO_FILE} Please fix or delete this read file."
      exit(1)
    end
  end

  def self.save_todos(todos)
    File.write(Config::TODO_FILE, todos.map(&:to_hash).to_json)
  end

  def self.index_todos(todos)
    todos.each_with_index do |todo, idx|
      todo.index = idx.to_s
    end

    todos
  end

  def self.today
    self.load_todos.select { |todo| todo.category == 'today' }
  end

  def self.done
    self.load_todos.select { |todo| todo.category == 'done' }
  end

  def self.upcoming
    self.load_todos.select { |todo| todo.category == 'upcoming' }
  end

  def self.by_category
    todos = {
      'today' => [],
      'upcoming' => [],
      'someday' => [],
      'repeaters' => [],
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
    hash
  end

  def mark_done
    @category = 'done'
    @completed_at = Time.now

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

  def self.update_for_schedules
    todos = Todo.load_todos

    todos.select(&:upcoming?).select(&:available?).each do |todo|
      todo.available_on = nil
      todo.category = 'today'
      todo.prioritize
    end
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
    'a'        => 'add',
    'add'      => 'add',
    'c'        => 'complete',
    'complete' => 'complete',
    'l'        => 'list',
    'list'     => 'list',
    'd'        => 'delete',
    'delete'   => 'delete',
    's'        => 'schedule',
    'schedule' => 'schedule',
    'p'        => 'priority',
    'priority' => 'priority',
    'h'        => 'help',
    '?'        => 'help',
    'help'     => 'help',
    'q'        => 'quit',
    'quit'     => 'quit',
    'clear'    => 'clear',
    'i'        => 'info',
    'info  '   => 'info',
    'cal'      => 'calendar',
    'calendar' => 'calendar',
  }

  CATEGORY_COLORS = {
    'today' => '{w ',
    'upcoming' => '{w ',
    'someday' => '{w ',
    'repeaters' => '{w ',
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
    show('upcoming', Todo.upcoming)
  end

  def show(category, todos)
    Display.say(CATEGORY_COLORS[category] + category.titleize + '}')

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

    return show_all if args == ['all'] || args == ['*']
    return show_done if args == ['done'] || args == ['d']
    return show_upcoming if args == ['upcoming'] || args == ['u']
    show_today
  end

  def clear(*_args)
    Display.say `tput reset`.chomp
  end

  def complete(*args)
    args.flatten!

    if args.size != 1
      Display.say("I don't understand what you want to do")
      return
    end

    id = args[0]

    unless todo = Todo.find(id)
      Display.say("I couldn't find a todo with an ID of #{id}")
      return
    end

    todo.mark_done
    list
  end

  def priority(*args)
    args.flatten!

    if args.size != 1
      Display.say("I don't understand what you want to do")
      return
    end

    id = args[0]

    unless todo = Todo.find(id)
      Display.say("I couldn't find a todo with an ID of #{id}")
      return
    end

    todo.prioritize
    list
  end

  def schedule(args)
    args.flatten!

    if args.size != 2
      Display.say("I don't understand what you want to do")
      return
    end

    id = args[0]
    date = args[1]

    unless todo = Todo.find(id)
      Display.say("I couldn't find a todo with an ID of #{id}")
      return
    end

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

  def delete(args)
    args.flatten!

    if args.size != 1
      Display.say("I don't understand what you want to do")
      return
    end

    id = args[0]

    unless todo = Todo.find(id)
      Display.say("I couldn't find a todo with an ID of #{id}")
      return
    end

    todo.delete
    list
  end

  # TODO
  def undo
  end

  def info(*_args)
    stats = Todo.by_category.map { |category, todos| "#{todos.size} Todos in #{category}" }
    stats.unshift "ToDoor v#{Config::VERSION}"

    Display.flowerbox(*stats, box_thickness: 0)
  end

  def help(*_args)
    Display.flowerbox(
      "ToDoor v#{Config::VERSION}",
      '',
      'Commands',
      '========',
      'add <text>, a <text> - Add a new Todo',
      'list, l, l t         - List today\'s Todos',
      'l *, l all           - List Todos in all categories',
      'l u                  - List Upcoming Todos',
      'l s                  - List Someday Todos',
      'l r                  - List Repeater Todos',
      'help, h, ?           - Display this text',
      'complete, c          - Mark a Todo as done',
      'delete, d            - Delete a Todo entirely',
      'clear                - Clear screen',
      'info, i              - Display Todoor version and stats',
      '',
      'Full documentation available here:',
      'https://github.com/Calamitous/todoor/blob/master/README.md',
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
        "ToDoor v#{Config::VERSION}",
        '',
        'Options',
        '========',
        '--schedule-update: Updates all the todos based on the current date',
        '  NOTE: This should be run with the following crontab:',
        "  1 0 * * * #{Config::TODOOR_SCRIPT} --schedule-update"
      )
      exit(0)
    end

    if ARGV.include?('--schedule-update')
      Todo.update_for_schedules
      exit(0)
    end

    Display.say "Welcome to ToDoor v#{Config::VERSION}.  Type 'help' for a list of commands; Ctrl-D or 'quit' to leave."
    show_today

    while line = readline("~> ") do
      handle(line)
    end
  end
end

StartUpper.new
