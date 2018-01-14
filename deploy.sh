#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
hugo # if using a theme, replace with `hugo -t <YOURTHEME>`

# Commit message.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
then msg="$1"
fi

# Commit and Push public submodule
cd public
git add .
git commit -m "$msg"
git push origin master

# Commit and Push project root
cd ..
git add .
git commit -m "$msg"
git push origin master
