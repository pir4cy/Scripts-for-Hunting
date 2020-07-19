#!/bin/bash

export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

#Banner 
banner()  #Create Banner
{
        figlet -ctkf slant $1
}

#Some Variables
toolsFolder="$HOME/tools" 
targetFolder=$1
input="$targetFolder/targets.txt"        #Pass in-scope file
avoid="$targetFolder/avoid.txt"        #pass out-scope file

cd $targetFolder
mkdir domains
cd domains
#Main Loop
while read line; do             

        mkdir $line
        cd $line

        clear
        banner "Subdomain Enum"
        
        #AMASS
        amass enum -src -ip -active -d $line -o amassoutput.txt
        cat amassoutput.txt | cut -d']' -f 2 | awk '{print $1}' | sort -u > hosts-amass.txt 

        #Subfinder
        subfinder -d $line -o hosts-subfinder.txt -silent 

        #AssetFinder
        assetfinder --subs-only $line >> hosts-assetfinder.txt 

        #Crt.sh
        curl -s "https://crt.sh/?q=%.$line&output=json" | jq '.[].name_value' | sed 's/\"//g' | sed 's/\*\.//g' | sort -u > hosts-crtsh.txt 
        curl -s https://certspotter.com/api/v0/certs\?domain\=$line | jq '.[].dns_names[]' | sed 's/\"//g' | sed 's/\*\.//g' | sort -u > hosts-certspotter.txt 


        #Remove dupes and join all data found
        cat hosts-amass.txt hosts-crtsh.txt hosts-certspotter.txt hosts-subfinder.txt hosts-assetfinder.txt | sort -u > hosts-all.txt 
        rm -rf hosts-amass.txt hosts-subfinder.txt hosts-assetfinder.txt hosts-crtsh.txt hosts-certspotter.txt

        #Remove out of scope items
        grep -vf $avoid hosts-all.txt > hosts-scope.txt 

        echo "Total number of subdomains"
        cat hosts-scope.txt | wc -l

        #Gau scan
        gau --subs $line | tee gau_urls.txt

        #WaybackUrl Output
        cat hosts-scope.txt | waybackurls > archive_urls.txt
        
        cat gau_urls.txt archive_urls.txt | sort -u > waybackurls.txt
        echo "Total Waybackurls"
        cat waybackurls.txt | wc -l

        echo "Checking for alive hosts"
       
        #MassDNS
        massdns -r $toolsFolder/massdns/lists/resolvers.txt -t A -o S -w $line-massdns.out hosts-scope.txt
        cat $line-massdns.out | awk '{print $1}' | sed 's/.$//' | sort -u > hosts-online.txt
        #httprobe
        cat hosts-online.txt | httprobe -c 50 -t 3000 > hosts-live.txt

        echo "Looking for vulnerable endpoints"
        mkdir gf_listing
        cat waybackurls.txt | gf redirect > gf_listing/redirect.txt
        cat waybackurls.txt | gf ssrf > gf_listing/ssrf.txt
        cat waybackurls.txt | gf rce > gf_listing/rce.txt
        cat waybackurls.txt | gf idor > gf_listing/idor.txt
        cat waybackurls.txt | gf sqli > gf_listing/sqli.txt
        cat waybackurls.txt | gf lfi > gf_listing/lfi.txt
        cat waybackurls.txt | gf ssti > gf_listing/ssti.txt
        cat waybackurls.txt | gf debug_logic > gf_listing/debug_logic.txt
        cat waybackurls.txt | gf intsubs > gf_listing/intsubs.txt

        #WAFCheck
        echo "WAF W00F"
        wafw00f -i hosts-scope.txt -o waf.txt

        #CORS misconfig
        echo "Checking for CORS misconfiguration"
        python3 $HOME/tools/Corsy/corsy.py -i hosts-live.txt -o corsy.json
        

        #Masscan
        clear
        banner "Masscan"
        cat $line-massdns.out | awk '{print $3}' | sort -u | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > ips-massdns.txt
        cat amassoutput.txt | cut -d']' -f 2 | awk '{print $2}' | sort -u > ips-amass.txt 
        cat ips-massdns.txt ips-amass.txt | sort -u > ips-online.txt
        masscan -iL ips-online.txt --rate 10000 -p1-65535 --open-only --output-filename $line-masscan.out

        #Checking for subdomain takeover
        clear
        banner "Subdomain Takeover"
        subjack -w hosts-online.txt -t 1000 -o $line-takeover.txt -v
        cd ..
        mv $line $line-done

done < $input
