#!/usr/bin/env tclsh86

# test-libcyg.tcl - test functionality of libcyg.tcl

# @note don't package require libcyg, but source it, easier to test.

package require tcltest
namespace import -force ::tcltest::*

package require ndv

# source ../libcyg.tcl
source [file normalize [file join [info script] .. .. libcyg.tcl]]

## test to_cygwin
test tc-1 {tc 1} {to_cygwin "c:/aaa"} "/cygdrive/c/aaa"
test tc-2 {tc 2} {to_cygwin "c:/"} "/cygdrive/c/"
test tc-3 {tc 3} {to_cygwin "/cygdrive/c/aaa"} "/cygdrive/c/aaa"
test tc-3 {tc 3} {to_cygwin [to_cygwin "c:/aaa"]} "/cygdrive/c/aaa"

## test from_cygwin
test fc-1 {fc} {from_cygwin "/cygdrive/c/aaa"} "c:/aaa"

# [2016-11-19 15:34] c: is returned, not c:/, for now okay.
test fc-2 {fc} {from_cygwin "/cygdrive/c/"} "c:"
test fc-3 {fc} {from_cygwin "c:/"} "c:/"
test fc-1 {fc} {from_cygwin [from_cygwin "/cygdrive/c/aaa"]} "c:/aaa"

## test if back and forth return orig.
## tests don't have to have unique names, see below.
test bf {bf} {to_cygwin [from_cygwin "/cygdrive/c/aaa"]} "/cygdrive/c/aaa"
test bf {bf} {from_cygwin [to_cygwin "c:/aaa"]} "c:/aaa"

cleanupTests
