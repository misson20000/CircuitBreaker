# Circuit Breaker

This is Circuit Breaker, an interactive Nintendo Switch hacking toolkit.

## Installation

Install Circuit Breaker through RubyGems.

    $ gem install circuitbreaker

Alternatively, you can clone the repository.

    $ git clone git@github.com:misson20000/CircuitBreaker.git
    $ cd CircuitBreaker/
    $ bundle

## Usage

There are currently two backends implemented: Faron, and Lanayru. Faron works with ELF core dumps from [Twili](https://github.com/misson20000/twili), whereas Lanayru connects through [Twili](https://github.com/misson20000/twili) and debugs an active process running on hardware.

This gem provides executables for each backend.

    $ faron coredump.elf # takes a path to a core dump
    [1] pry(#<CircuitBreaker::Faron::InteractiveDSL>)> quit
    $ lanayru 0x57 # takes a process ID
    [1] pry(#<CircuitBreaker::Faron::InteractiveDSL>)>

If you are working with a checked out repo, use `bundle exec`.

    $ bundle exec faron coredump.elf

Until I write new documentation, refer to the [old verion's README](https://github.com/misson20000/CircuitBreaker-archive/blob/master/README.md).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/misson20000/CircuitBreaker.
