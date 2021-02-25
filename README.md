# FingerStrings
## The simplest Todo list

FingerStrings is a tiny script that is a sort-of todo list, with recurrence and schedulable todos.

FingerStrings is strictly text-based, requiring no GUI or web servers.

 * [Usage](#usage)
 * [Installation](#installation)
 * [Commands](#commands)
 * [Command-line Options](#command-line-options)
 * [Philosophy](#philosophy)
 * [Tests](#tests)
 * [Technical Bits](#technical-bits)
 * [License](#license)


Crontab:
```
1 0 * * * ~/Projects/finger_strings/finger_strings.rb --schedule-update
```

# Tests

`gem install --user-install minitest`
`gem install --user-install mocha`

