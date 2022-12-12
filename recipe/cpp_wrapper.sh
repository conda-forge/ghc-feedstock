#!/bin/bash

for arg do
  shift
  [[ "$arg" == -march* ]] && continue
  [[ "$arg" == -mtune* ]] && continue
  [[ "$arg" == -mcpu* ]] && continue
  set -- "$@" "$arg"
done

exec CPP $@
