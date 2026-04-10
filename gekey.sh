#!/bin/bash
cd files
names=("hq" "sede1" "sede2" "sede3" "sede4")
for i in ${names[@]}; do
	wg genkey | tee "${i}".key | wg pubkey > "${i}.pub"
done
