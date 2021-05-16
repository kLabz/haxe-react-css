#!/bin/sh

set -e
haxe build.hxml
haxe build-salt.hxml
diff out expected
