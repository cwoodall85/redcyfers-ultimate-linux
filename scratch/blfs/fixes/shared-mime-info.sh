#!/bin/bash
# The book marks shared-mime-info's test step role="test", which the
# generator emits as ordinary commands. The tests need the xdgmime
# subproject, which meson would fetch with git (not installed). Tests are
# off for this build: drop the step.
sed -i '/^meson configure -D build-tests=true$/d; /^ninja test$/d' "$1"
