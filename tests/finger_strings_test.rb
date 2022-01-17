require 'minitest/autorun'
require 'mocha/minitest'

# This forces the script to load the test file instead of the user's actual
# todo file
$test_todo_file = "./tests/.finger_strings"

require './finger_strings.rb'

describe Config do
  it 'has the Iris semantic version number' do
    Config::VERSION.must_match /^\d\.\d\.\d+$/
  end

  it 'has the readline history file location' do
    Config::HISTORY_FILE.must_match /\.finger_strings\.history$/
  end

  it 'starts with an empty list of todos' do
    Config::EMPTY_TODOS.must_equal []
  end

  it 'has the todo file location' do
    Config::todo_file.must_equal "./tests/.finger_strings"
  end
end

describe Todo do
  describe '#mark' do
    it 'set the marker to the current todo\'s index' do
      assert_nil Display.marker

      todos = Todo.today
      todo = todos.first

      todo.mark

      p todo.index
      p "!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      p Display.marker
      p "!!!!!!!!!!!!!!!!!!!!!!!!!!!"

      Display.marker.must_equal todo.index
    end
  end

  describe '#prioritize' do
    it 'moves the selected todo to the top of the list'
  end
end
