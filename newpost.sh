#!/bin/bash

read -p "Title: " title
read -p "Summary: " summary
read -p "Tags: " tags

IFS=$'\n'

date=$(date +"%Y-%m-%d")
time=$(date +"%H-%M-%S")

escaped=$(echo -en $title | tr '[:upper:]' '[:lower:]' | perl -pe "s/\s/_/g")

if [ ${escaped: -1:1} = '.' ]; then
	escaped=${escaped:0:${#escaped}-1}
fi

file="_posts/$date-$time-$escaped.md"

border="---"
layout="layout:\t\tpost"
title="title:\t\t$title"
summary="summary:\t"$summary
date="date:\t\t$date $time"
tags="categories:\t"${tags[@]}

stream=$border
lines=($layout $title $summary $date $tags $border)

for i in ${lines[@]}; do
	stream="$stream\n$i"
done

echo -e $stream > $file

echo -e "Done \033[91m<3\033[0m"