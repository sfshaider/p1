#!/bin/sh
GREEN='\033[00;32m';
NC='\033[0m';
echo -e "${GREEN}#####################################";
echo -e "${GREEN}#           RUNNING TESTS           #";
echo -e "${GREEN}#####################################${NC}"
for d in ./tests/*.t; do (perl "$d"); done
echo -e "${GREEN}#####################################";
echo -e "${GREEN}#           FINISHED TESTS          #";
echo -e "${GREEN}#####################################${NC}"

