#!/bin/env perl

echo "Executing genfiles.pl followed by putfiles.pl if genfiles.pl exits cleanly"
./genfiles.pl && ./putfiles.pl
echo "Execution complete"