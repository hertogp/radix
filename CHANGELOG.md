# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a
Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [v0.4.0] - 2021-12-04

### added

- `Radix.get_and_update/3` to get & update a key,value-pair in one pass (exact match).

### changed

- `Radix.less/3`, now optionally excludes given search key from the results
- `Radix.more/3`, now optionally excludes given search key from the results


## [v0.3.0] - 2021-07-24

### added

- `Radix.adjacencies/1`, returns a map of parent keys with their (combinable) children
- `Radix.prune/3` prune a tree by combining neighboring keys, recursion is optional

### changed

- `Radix.count/1` raises ArgumentError instead of FunctionClauseError on invalid input


## [v0.2.0] - 2021-07-18

### changed

- `Radix.fetch/3` now can optionally use longest prefix match
- functions raise their own errors
- use assets subdir for images

### added

- `Radix.empty?/1`, says if a `tree` is empty or not
- `Radix.count/1`, traverses the `tree` and counts its entries
- `Radix.merge/2`, merges `tree2` into `tree1`, overriding `tree1`
- `Radix.merge/3`, merges `tree2` into `tree1`, conflicts handled by `fun`
- `Radix.take/3`, returns new tree with selected `keys` only
- `Radix.pop/3`, removes key,value-pair and returns it with the new tree
- `Radix.split/3`, split a radix tree into two trees


## [v0.1.1] - 2021-06-21

### changed

- bad_xxx functions were meant to be private

# [v0.1.0] - 2021-06-21

Initial version.
