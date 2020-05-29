#!/bin/bash

#Setting GOPATH
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

#Banner 
banner()  #Create Banner
{
        figlet -ctkf slant $1
}

#Some Variables

mainFolder="$HOME/bugHunting/"
toolsFolder="$HOME/tools"
scopeFolder="$mainFolder/targetScopes"
input=$1

#Main Loop
while read line; do

        cd $mainFolder
        mkdir $line
        cd $line

        clear
        banner "Recon Tool"
        
        #AMASS
        amass enum -src -ip -active -d $line >> amassoutput.txt
        cat amassoutput.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > hosts-amass.txt &
        cat amassoutput.txt | cut -d']' -f 2 | awk '{print $2}' | sort -u > ip-amass.txt &

        #Subfinder
        subfinder -d $line -o hosts-subfinder.txt -silent &

        #AssetFinder
        assetfinder --subs-only $line >> hosts-assetfinder.txt &

        #Crt.sh
        curl -s "https://crt.sh/?q=%.$line&output=json" | jq '.[].name_value' | sed 's/\"//g' | sed 's/\*\.//g' | sort -u > hosts-crtsh.txt &
        curl -s https://certspotter.com/api/v0/certs\?domain\=$line | jq '.[].dns_names[]' | sed 's/\"//g' | sed 's/\*\.//g' | sort -u > hosts-certspotter.txt &

        wait

        #Remove dupes and join all data found
        cat hosts-amass.txt hosts-crtsh.txt hosts-certspotter.txt hosts-subfinder.txt hosts-assetfinder.txt | sort -u > hosts-all.txt 
        rm -rf amassoutput.txt hosts-amass.txt hosts-subfinder.txt hosts-assetfinder.txt hosts-crtsh.txt hosts-certspotter.txt

        #Remove out of scope items
        #grep -vf $scopeFolder/$line-ignore.txt hosts-all.txt > hosts-inscope.txt 

        #Checking for alive hosts

        #MassDNS
        massdns -r $toolsFolder/massdns/lists/resolvers.txt -t A -o S -w $line-massdns.out hosts-inscope.txt
        cat $line-massdns.out | awk '{print $1}' | sed 's/.$//' | sort -u > hosts-online.txt

        #Checking for subdomain takeover
        clear
        banner "Subdomain Takeover"
        subjack -w hosts-online.txt -t 1000 -o $line-takeover.txt -v

        #Masscan
        clear
        banner "Masscan"
        cat $line-massdns.out | awk '{print $3}' | sort -u | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > ips-online.txt
        masscan -iL ips-online.txt --rate 10000 -p1-65535 --open-only --output-filename $line-masscan.out


done < $input
