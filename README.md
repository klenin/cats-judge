# Automated judging system for programming contests.
[![Build Status](https://travis-ci.org/klenin/cats-judge.svg?branch=master)](https://travis-ci.org/klenin/cats-judge)

`cats-judge` can be used either as a component of [CATS](https://github.com/klenin/cats-main) contest control system or
as a standalone command-line application for both competitors and problem authors.

Licensed under GPL v2 or later, see COPYING file.

## Features

For competitors:
* Explore different solutions for a problem by running various combinations of solutions and tests.
* Debug your solution without the need for constant web UI access.

For problem authors:
* Compare different partial solutions to choose time and memory limits.
* Increase you efficiency by accessing the power of command line.
* Use with `git` or any other version control system to develop programming problems in a modern workflow.
* Conveniently upload your problem into contest control system when it is ready.

## Prerequisites

`cats-judge` requires [Perl](https://www.perl.org/) 5.12 or later and `git` of any version.

Current version supports various Windows flavors, from Windows XP to Windows 10.
Other platforms are currently in *experimental* state.
Some features may be missing or unstable.

Nevertheless, `cats-judge` was at least lightly tested on Debian, Red Hat, Ubuntu, OS X and OpenBSD.

It is recommended to use [Strawberry Perl](http://strawberryperl.com) distribution on Windows,
but [Active State Perl](http://www.activestate.com/activeperl) was also reported to be working.

At least some programming languages, such as C++ and Pascal should be installed to actually judge solutions.

## Installation

  * Make sure your `perl` and `git` are in `PATH`
  * Clone this repository
  * Run `perl install.pl`
  * See [Advanced installation](#advanced-installation) in case of problems

## Usage

This covers using `cats-judge` as a command-line utility.
To use as a judging server, refer to `cats-main` documentation.

It is recommended to run `cats-judge` via starting script which is located
in either `cmd/j.cmd` or `cmd/j.sh` depending on the platform.
Subdirectory `cmd` should be added to `PATH` during installation, so
a typical command line invocation should look like

```
j <command> <options>
```

All commands and options may be abbreviated.
Options may start from either single or double dash.

### `install` command

Install problem for future solving.
Installation includes folowing steps:
  * check problem cache
  * parse problem description
  * compile all sources
  * generate test files
  * run standard solution to get test answers
  * cache tests and executables

Options:
  * `--problem <zip_or_directory_or_name>` required
  * `--force-install` install problem even if it is already cached

Example:
```
j install --problem aplusb.zip --force-install
```
Install problem from file `aplusb.zip`, ignore cache.
```
j i -p .
```
Install problem from the current directory.

### `run` command

Run one or more problem solutions.
Running includes folowing steps:
  * install problem as per `install` command
  * detect compiler/interpreter (aka *development environment*)
  * compile solution
  * run solution on problem tests
  * display results

Options:
  * `--problem <zip_or_directory_or_name>` required
  * `--run <source_file>` required. Path to solution source. May be repeated.
  * `--de <de_code>` enforce development environment. By default development environment is detected by file extension.
  * `--force-install` install problem even if it is already cached
  * `--testset <testset>` test only on a subset of tests. By default all tests are used.
  * `--result text|html` display results in a given format. Format `text` (default) displays ASCII table on console. Format `html` saves report in `html` file.
  * `result-columns <regexp>` display only columns corresponding to this filter.

Examples:
```
j run A.zip -run mysolution.py
```
Test solution `mysolution.cpp` for problem `A.zip`.
Solution is probably written in Python.
```
j run . -run good.cpp -run bad.cpp -result-columns="Test|Result"
```
Test two solutions for a problem located in the current directory,
display only test number and test result code for each test.
```
j run B.zip -run sol.pas -t 1,3,12-15 -format=polygon
```
Test solution `sol.pas` for a Polygon-style problem.
Run only tests 1, 3,  12, 13, 14 and 15.

```
j run B.zip -run sol.cpp -de 102
```
Enforce GCC compiler for solution.

### `download` command

Download problem from web-based contest control system.
Request credentials if needed.

Options:
  * `--problem <zip_or_directory_or_name>` required
  * `--url <url>` required
  * `--system cats|polygon` use given Web API. By default system is detected based on URL prefix.

### `upload` command

Upload problem to web-based contest control system.
Request credentials if needed.

Options:
  * `--problem <zip_or_directory_or_name>` required
  * `--url <url>` required
  * `--system cats|polygon` use given Web API. By default system is detected based on URL prefix.

### `config` command

Work with configuration.

Options:
  * `--print <regexp>` print configuration

Examples:
```
j config --print def_DEs
```
Display default development environment codes for each extension.

```
j conf -p url
```
Display contest control system URL prefixes.

### `clear-cache` command

Remove problem from the cache. Note that if the problem exports some modules,
they will become orphaned and may break dependent problems.

Options:
  * `--problem <zip_or_directory_or_name>` required

### `serve` command

Start judging server.

### `help` command

Display basic usage.

### Common options

  * `--config-set <name>=<value> ...` set configuration value before running the command. For example
     ```
     j run -p A.zip -run a.cpp -config-set rundir=./tmp
     ```
  * `--db` import modules from databale
  * `--format cats|polygon` use given problem format. Default is `cats`.
  * `--verbose` display additional debug info

## Advanced installation

### Antivirus

Since `cats-judge` creates, copies and removes multiple executables in
the course of operation, it may conflict with some antivirus software.

Usually conflicts are manifested by slow testing (several seconds per test) and/or intermittent error messages.

You may want to exclude `cats-judge` directory from antivirus monitoring.

### Installation options

Installation script performs some complex operations, which may require manual intervention.
Script has following command line options:
  * `--step <N>...` may be repeated. Perform only a given steps of installation. By default, all steps are performed. You may run `perl install.pl -s 99` to see a list of steps without running any.
  * `--devenv <devenv-filter>` only detect development environments containing given string. By default, all known environments are detected.
  * `--modules <modules-filter>` only install modules containing given string. By default, all modules are installed.
  * `--verbose` display additional debug info
