#!/bin/bash

#===========================================================
function ShowCopyright ()
{
cat << \EOF
################################################################################
# SSS.SH is program that analyzes the SystemState developed by Shunya suzuki.
# Copyright (C) 2015 CO-Sol Inc.
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
# License for more details.
# 
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
################################################################################
EOF
#-----------------------------------------------------------
}


# History
# ~~~~~~~
#   0. shunya.suzuki@cosol.jp     v1.0.0a1   2014/09/16
#      start
#   1. shunya.suzuki@cosol.jp     v1.0.0a2   2014/10/06
#      implement   - add matrix output method
#      refactoring - ???
#   2. shunya.suzuki@cosol.jp     v1.0.0b1   2014/11/15
#      implelemt   - add lock detect method(terminal psr)
#      +--+-------------------------+--+---+---+---+---+---+
#      |  |                         |9i|10g|10g|11g|11g|12c|
#      |No|feature                  |R2|R1 |R2 |R1 |R2 |R1 |
#      +--+-------------------------+--+---+---+---+---+---+
#      | 1|enqueue                  |o | o | o | o | o | o |
#      | 2|latch                    |d | o | o | o | o | d |
#      | 3|mutex                    |- | - | o | o | o | o |
#      | 4|row cache enqueue(rcache)|x | x | x | x | o | o |
#      | 5|library cache lock(lock) |o | o | o | o | o | o |
#      | 6|library cache pin(pin)   |o | o | o | o | o | o |
#      +--+-------------------------+--+---+---+---+---+---+
#      o:testcase
#      x:no testcase,no test
#      -:not implement in oracle db
#      d:test with debugger
#   3. shunya.suzuki@cosol.jp     v1.0.0b3   2015/01/02
#      bug fix     - how to analysis Session SO
#      extension   - sstree(beta
#   4. shunya.suzuki@cosol.jp     v1.0.0     2015/01/09
#      enhance     - how to analysis 'enq convert'
#      extension   - hungchk(beta
#   5. shunya.suzuki@cosol.jp     v1.0.0     2015/05/31
#      refactoring - japanese comments into english
#   6. shunya.suzuki@cosol.jp     v1.0.1     2015/06/03
#      implement   - add html report mode
#      refactoring - change progress output method(stdout -> use /dev/stderr)
#   7. shunya.suzuki@cosol.jp     v2.0.0     2015/06/29
#      refactoring - change file type(awk -> sh)
#                    add several function
#                      o analyze the running sql
#                      o summary Proc/SessSO
#                    some extension is removed temporarily 


#===========================================================
# awk script - common function
#-----------------------------------------------------------
function ShowAwkCommonFunction ()
{
cat << \EOF
#===========================================================
# Function - common function
#-----------------------------------------------------------

# Function : MID
# get the characters enclosed by the specified patterns.
function MID(str,pattern1,pattern2,   idx){
   if(pattern1!="" && pattern2!=""){                        #when specified both pattern1,pattern2
      if(index(str,pattern1)==0) return ""
      idx=index(str,pattern1) + length(pattern1)-1          #get the characters enclosed by the parameters
      str=substr(str,idx+1,length(str)-idx)
      str=substr(str,1,index(str,pattern2)-1)
   }else if(pattern2==""){                                  #when specified only pattern1
      idx=index(str,pattern1) + length(pattern1)-1          #get pattern1 subsequent characters
      str=substr(str,idx+1,length(str)-idx)
   }else if(pattern1==""){                                  #when specified only pattern2
      idx=index(str,pattern2)-1                             #get pattern1 previous characters
      str=substr(str,1,idx)
   }
   return str
}

# Function : ElemN
# get the n-th string separated by specified character.
function ElemN(str,pattern,n,   arr){
  split(str,arr,pattern)
  return arr[n]
}

# Function : Replace,Remove
# this function like sub,but get replaced characger
# instead substitution number of times.
# (this function can be replaced in gensub in gawk)
function Replace(str,r,s){gsub(r,s,str);return str}
function Remove(str,r)   {return Replace(str,r,"")}

# Function : Repeat
# get the characters repeated specified character.
function Repeat(s,n,   r,i) {for(;i<n;i++) r=r s;return r}

# Function : Trim
# get the trimed charactes
function TrimL(s){sub(/^[ \t\n]+/, "", s); return s}
function TrimR(s){sub(/[ \t\n]+$/, "", s); return s}
function Trim(s) {return TrimR(TrimL(s))}

# Function : NVL
# get 1st value if its not blank.
# (if 1st value is blank, return 2nd value.)
function NVL(p1,p2){if(p1!=""){return p1}else{return p2}}

# Function : BreakedStr
# get the character folded in the number of characters that you specified.
# in :s string that you wanna insert line break
#    :w position for line break
function BreakedStr(s,w,   i,j,ret,arr){
   split(s,arr,"\n")                                        #consider case that a new line is included
   for(i=1;i<=length(arr);i++)                              #by the separated elements by a newline
      for(;j<=int(length(arr[i])/w);j++)                    #specified width
         ret=sprintf("%s%s\n", ret, substr(arr[i],j*w,w))
   return TrimR(ret)                                        #return to remove the terminating newline
}

# Function : HtmlEncStr
# get html encoded string
# in :str string that you wanna encode
function HtmlEncStr(str,   arr1,arr2,i){
   split("&, ,\",<,>,/",arr1,",")
   split("\\&amp;,\\&nbsp;,\\&quot;,\\&lt;,\\&gt;,\\&frasl;",arr2,",")
   for(i=1;i<=length(arr1);i++)
      str=Replace(str,arr1[i],arr2[i])                      #pattern1
      #gsub(arr1[i],arr2[i],str)                            #pattern2
      #str=gensub(arr1[i],arr2[i],"g",str)                  #pattern3
   return str
}
#   I wondered if pattern2,3 is faster than pattern1, so I confirmed
#   the processing time of pattern1,2,3 using the following code.
#   as a result, there was hardly any difference.
#   
#   $echo " ,\",&,<,>,/" | time awk '
#   > function Replace(str,r,s){gsub(r,s,str);return str}
#   > function HtmlEncStr(str,   arr1,arr2,i){..... omit}
#   > {
#   >    for(i=1;i<=100000;i++) HtmlEncStr($0)
#   >    print "Elapsed Time: " end_time - start_time " (sec)";
#   > }'
#   5.95user 0.00system 0:05.96elapsed 99%CPU (0avgtext+0avgdata 552960maxresident)k
#   0inputs+0outputs (2230major+0minor)pagefaults 0swaps

# Funciton : Max
# get the number of large value.
# exception pattern assumes that you are numeric input value without taking into account
function Max(n1,n2){
   if(n1>n2) return n1
   return n2
}

# Function : IsNum
# return 1 if its number
# else return 0
function IsNum(n){return (n~"^-?0?\\.?[0-9]+$")}

# Function : ExistArr
# return true, if exist specified pattern in arr
function ExistArr(arr,pattern,   i){
   for(i=1;i<=length(arr);i++){
      if(arr[i]==pattern) return 1
   }
   return 0
}

# Function : IndexArr
# returns the subscript if the specified value exists
# else return -1
function IndexArr(arr,str,   i){
   for(i in arr) if(arr[i]==str) return i
   return -1
}

# Function : AddItem
# set specified value at [number of items in arr]+1
function AddItem(arr,val){arr[length(arr)+1]=val}

EOF
}


#===========================================================
# awk script - ss.awk
#-----------------------------------------------------------
function ShowAwkSs ()
{
cat << \EOF
#===========================================================
# Function - ss.awk
#-----------------------------------------------------------

# Function : InitMaxLenMtx
function InitMaxLenMtx(arr1,arr2,   i){
   for(i=1;i<=length(arr2);i++) arr1[i]=length(arr2[i])
}

# Function : SetMaxLenMtx
function SetMaxLenMtx(arr1,arr2,   i,j,val,len){
   for(i in arr2){
      val=arr2[i]
      j=ElemN(i,SUBSEP,3)
      len=length(val)
      if(arr1[j]<len) arr1[j]=len
   }
}

# Function : SetFmtMtx
# arr1 : format(return arr2+arr3)
# arr2 : length
# arr3 : number("") or string("-")
function SetFmtMtx(arr1,arr2,arr3,   i){
   for(i=1;i<=length(arr2);i++)
      arr1[i]=sprintf("%%%s%ss",arr2[i],arr3[i])
}

# Function : GetHdrTtlMtx
# arr1 element(title name)
# arr2 format
function GetHdrTtlMtx(arr1,arr2,   ret,i){
   ret=C_OUTPUT_RESULT_WITH_BLANK
   for(i=1;i<=length(arr1);i++){
      ret=ret sprintf(arr2[i],arr1[i])
      if(i!=length(arr1)) ret=ret C_SEP
   }
   return ret
}

# Function : OutputHdrTtlMtxHtml
# arr1 element(title name)
function OutputHdrTtlMtxHtml(arr1,   i){
   print("<thead><tr>")
   for(i=1;i<=length(arr1);i++)
      printf("<th>%s</th>",arr1[i])
   print("</tr></thead>")
}

# Function : SetHdrMtxExLen
# csv1 stop list
# arr1 len list
function SetHdrMtxExLen(csv1,arr1,arr2,   i,j,s,arr3){
   split(csv1,arr3,",")
   s=j=0
   for(i=1;i<=length(arr1);i++){
      if(ExistArr(arr3,i)){
         arr2[++j]=--s
         s=0
      }
      s+=arr1[i]+1
   }
   arr2[++j]=--s
}

# Function : GetHdrTtlMtxEx
# csv1 stop list
# csv2 element(title name)
# arr1 len list
function GetHdrTtlMtxEx(csv1,csv2,arr1,   i,f,arr2,arr3,ret){
   ret=C_OUTPUT_RESULT_WITH_BLANK
   SetHdrMtxExLen(csv1,arr1,arr2)
   split(csv2,arr3,",")
   for(i=1;i<=length(arr2);i++){
      f=sprintf("%%%s-s",arr2[i])
      ret=ret sprintf(f,arr3[i])
      if(i!=length(arr2)) ret=ret C_SEP
   }
   return ret
}

# Function : OutputHdrTtlMtxExHtml
# csv1 stop list
# csv2 element(title name)
# arr1 len list
function OutputHdrTtlMtxExHtml(csv1,csv2,arr1,   i,f,arr2,arr3,ret){
   SetHdrMtxExLen(csv1,arr1,arr2)
   split(csv1,arr2,",")
   split(csv2,arr3,",")
   AddItem(arr2,length(arr1) - arr2[length(arr2)])
   printf("<thead><tr align=\"left\">")
   for(i=1;i<=length(arr3);i++){
      printf("<th colspan=%s>%s</th>",arr2[i],arr3[i])
   }
   print("<tr></thead>")
}

# Function : GetHdrSepMtx
function GetHdrSepMtx(arr1,   ret,i){
   ret=C_OUTPUT_RESULT_WITH_BLANK
   for(i=1;i<=length(arr1);i++){
      ret=ret Repeat("-",arr1[i])
      if(i!=length(arr1)) ret=ret C_SEP
   }
   return ret
}

# Function : GetHdrSepMtxEx
# csv1 stop list
# arr1 len list
function GetHdrSepMtxEx(csv1,arr1,   arr2,ret,i){
   SetHdrMtxExLen(csv1,arr1,arr2)
   ret=C_OUTPUT_RESULT_WITH_BLANK
   for(i=1;i<=length(arr2);i++){
      ret=ret Repeat("-",arr2[i])
      if(i!=length(arr2)) ret=ret C_SEP
   }
   return ret
}

# Function : OutputMtx
# arr1 data
# arr2 format
# arr3 row count
function OutputMtx(arr1,arr2,arr3,i,   j,k,val){
   for(j=1;j<arr3[i];j++){
      printf C_OUTPUT_RESULT_WITH_BLANK
      for(k=1;k<=length(arr2);k++){
         val=Replace(arr1[i,j,k]," ",C_PRINT_IN_PLACE_BLANK)
         printf(arr2[k],val)
         if(k!=length(arr2)) printf C_SEP
      }
      printf "\n"
   }
}

# Function : OutputMtxHtml
# arr1 data
# arr2 format
# arr3 row count
function OutputMtxHtml(arr1,arr2,arr3,i,   j,k,val,fmt){
   printf("<tbody>")
   for(j=1;j<arr3[i];j++){
      printf("<tr>")
      for(k=1;k<=length(arr2);k++){
         val=Replace(arr1[i,j,k]," ",C_PRINT_IN_PLACE_BLANK)
         val=HtmlEncStr(val)
         align=(arr2[k]=="" ? "align=\"right\"" : "")
         printf("<td %s>%s</td>",align,val)
      }
      print("</tr>")
   }
   printf("</tbody>")
}

# Function : AddRes
# arr : manage resource("_holder or _waiter")
# sc  : SystemstateCount
# pid : oracle pid
# id  : resource id
# type: locking type
# mode: mode/request level
# evt : wait event
function AddRes(arr,sc,pid,id,type,mode,evt,   cnt){
   arr[sc,"cnt"]++
   cnt=arr[sc,"cnt"]
   arr[sc,cnt,"pid"]=pid
   arr[sc,cnt,"id"]=id
   arr[sc,cnt,"type"]=type
   arr[sc,cnt,"mode"]=mode
   arr[sc,cnt,"event"]=evt
   if(type=="latch"){
      arr[sc,cnt,"event"]="not implement yet. see above"
      arr[sc,cnt,"mode"]="N/A"
   }
}

# Function : AddRes
# get enq-name from NameAndType parameter
function GetNameAndType(p1,   val1,val2){
   val1=sprintf("%c",strtonum("0x" substr(p1,1,2)))
   val2=sprintf("%c",strtonum("0x" substr(p1,3,2)))
   return sprintf("%s%s",val1,val2)
}

# Function : SetProcSessElem
# set each element of proc / sess state
function SetProcSessElem(){
   if(_ver>=92) {AddItem(e2,"pid");       AddItem(f2,"")}   #v$process.pid
   if(_ver>=92) {AddItem(e2,"addr");      AddItem(f2,"")}   #v$process.addr
   if(_ver>=92) {AddItem(e2,"user");      AddItem(f2,"")}   #v$process.username
   if(_ver>=92) {AddItem(e2,"term");      AddItem(f2,"-")}  #v$process.terminal
   if(_ver>=92) {AddItem(e2,"ospid");     AddItem(f2,"")}   #v$process.spid
   if(_ver>=92) {AddItem(e2,"image");     AddItem(f2,"-")}  #v$bgprocess.name
   
   if(_ver>=92) {AddItem(e4,"saddr");     AddItem(f4,"")}   #v$session.saddr
   if(_ver>=102){AddItem(e4,"sid");       AddItem(f4,"")}   #v$session.sid
   if(_ver>=111){AddItem(e4,"ser");       AddItem(f4,"")}   #v$session.serial#
   if(_ver>=102){AddItem(e4,"service");   AddItem(f4,"-")}  #v$session.service_name(10.2.0.4 -)
   if(_ver>=92) {AddItem(e4,"username");  AddItem(f4,"-")}  #v$session.username(Oracle User Name)
   if(_ver>=92) {AddItem(e4,"process");   AddItem(f4,"")}   #v$session.process(OS の Client Process ID)
   if(_ver>=92) {AddItem(e4,"term");      AddItem(f4,"-")}  #v$session.terminal
   if(_ver>=92) {AddItem(e4,"cli_info");  AddItem(f4,"-")}  #v$session.client_info(dbms_application_info.set_client_info)
   if(_ver>=92) {AddItem(e4,"module");    AddItem(f4,"-")}  #v$session.module
   if(_ver>=92) {AddItem(e4,"action");    AddItem(f4,"-")}  #v$session.action
   if(_ver>=92) {AddItem(e4,"machine");   AddItem(f4,"-")}  #v$session.machine
   if(_ver>=92) {AddItem(e4,"osuser");    AddItem(f4,"-")}  #v$session.osuser
   if(_ver>=92) {AddItem(e4,"program");   AddItem(f4,"-")}  #v$session.program
   if(_ver>=92) {AddItem(e4,"command");   AddItem(f4,"-")}  #v$session.command
   if(_ver>=92) {AddItem(e4,"sql_addr");  AddItem(f4,"")}   #v$session.sql_address
   if(_ver>=92) {AddItem(e4,"block_sess");AddItem(f4,"")}   #v$session.blocking_session
   if(_ver>=92) {AddItem(e4,"wait_time"); AddItem(f4,"")}   #(v$session.wait_time)
   if(_ver>=92) {AddItem(e4,"seq");       AddItem(f4,"")}   #v$session.seq#
   if(_ver>=92) {AddItem(e4,"event");     AddItem(f4,"-")}  #v$session.event
}

# Function : OutputTextReport
function OutputTextReport(){
   #========================================================
   #get length,format
   #--------------------------------------------------------
   #---proc/sess state
   InitMaxLenMtx(l24,e24)                                   #initialize each element by element-name
   SetMaxLenMtx(l24,d24)                                    #set each element's length
   SetFmtMtx(fmt24,l24,f24)                                 #set each element's format
   httl24=GetHdrTtlMtx(e24,fmt24)                           #set header
   hsep24=GetHdrSepMtx(l24)                                 #set header(separator)
   httl24ex=GetHdrTtlMtxEx(en2+1,"proc state,sess state",l24)#set (extra)header
   hsep24ex=GetHdrSepMtxEx(en2+1,l24)                        #set (extra)header(separator)
   #---waiter/holder
   InitMaxLenMtx(lWH,eWH)                                   #initialize each element by element-name
   SetMaxLenMtx(lWH,dWH)                                    #set each element's length
   SetFmtMtx(fmtWH,lWH,fWH)                                 #set each element's format
   httlWH=GetHdrTtlMtx(eWH,fmtWH)                           #set header
   hsepWH=GetHdrSepMtx(lWH)                                 #set header(separator)
   httlWHex=GetHdrTtlMtxEx(enW+1,"waiter,holder",lWH)       #set (extra)header
   hsepWHex=GetHdrSepMtxEx(enW+1,lWH)                       #set (extra)header(separator)
   #========================================================
   #output
   #--------------------------------------------------------
   for(i=1;i<=_sc;i++){
      tmp=sprintf("%s.%s,%s",i,_s[i,"ts"],_s[i,"fn"])       #title
      printf("\n\n\n%s\n%s",tmp,Repeat("~",length(tmp)))    #title
      #---proc/sess state
      tmp=C_OUTPUT_RESULT_WITH_BLANK
      printf("\n%s%s\n%s%s\n",tmp,"proc/sess state summary",tmp,Repeat("~",23)) #title
      printf("%s\n%s\n%s\n%s\n%s\n",hsep24ex,httl24ex,hsep24,httl24,hsep24)
      OutputMtx(d24,fmt24,rn24,i)
      print hsep24
      #---waiter/holder
      printf("\n%s%s\n%s%s\n",tmp,"waiter/holder summary",tmp,Repeat("~",21)) #title
      if(length(dWH)==0){                                   #if no waiter
         print "couldn't detect waiter."                    #
      }else{
         printf("%s\n%s\n%s\n%s\n%s\n",hsepWHex,httlWHex,hsepWH,httlWH,hsepWH)
         OutputMtx(dWH,fmtWH,rnWH,i)
         print hsepWH
      }
   }
   if(analyze_sql){
      printf("\n%srunning sql(addr:sql_text)\n%s%s\n",tmp,tmp,Repeat("~",26))
      for(key in _sql) printf("%s : %s\n",key,_sql[key])
   }
   print("\n\n\nSSS.SH - Copyright(C) 2015 CO-Sol Inc.")
}

# Function : OutputHtmlReport
function OutputHtmlReport(){
   #========================================================
   #output
   #--------------------------------------------------------
   for(i=1;i<=_sc;i++){
      tmp=sprintf("%s.%s,%s",i,_s[i,"ts"],_s[i,"fn"])               #title
      printf("<br><br><br>%s<br>%s",tmp,Repeat("~",length(tmp)))    #title
      #---proc/sess state
      tmp=C_OUTPUT_RESULT_WITH_BLANK
      printf("<br>%s%s<br>%s%s<br>",tmp,"proc/sess state summary",tmp,Repeat("~",23)) #title
      print("<table border=1 cellspacing=0 class=\"stdn\">")
      OutputHdrTtlMtxExHtml(en2,"proc state,sess state",e24)
      OutputHdrTtlMtxHtml(e24)
      OutputMtxHtml(d24,f24,rn24,i)
      print("</table>")
      #---waiter/holder
      printf("<br>%s%s<br>%s%s<br>",tmp,"waiter/holder summary",tmp,Repeat("~",21)) #title
      if(length(dWH)==0){                                   #if no waiter
         print "couldn't detect waiter."                    #
      }else{
         print("<table border=1 cellspacing=0 class=\"stdn\">")
         OutputHdrTtlMtxExHtml(enW,"waiter,holder",eWH)
         OutputHdrTtlMtxHtml(eWH)
         OutputMtxHtml(dWH,fWH,rnWH,i)
         print "</table>"
      }
   }
   if(analyze_sql){
      printf("<br>running sql<br>%s",Repeat("~",11))
      print("<table border=1 cellspacing=0 class=\"stdn\">")
      print("<thead><th>sql_addr</th><th>sql_text</th></thead><br>")
      for(key in _sql){
         tmp1=HtmlEncStr(key)
         tmp2=HtmlEncStr(_sql[key])
         printf("<tr><td>%s</td><td>%s</td></tr>\n",tmp1,tmp2)
      }
      print("</table>")
   }
   #if analyze_sum option is enabled, 
   if(analyze_sum){
      print("<!--")
      OutputTextReport()
      print("-->")
   }
   printf("<div id=footer>SSS.SH - Copyright(C) 2015 CO-Sol Inc.</div><body></html>")
}

function OutputHeadCssScript(){

   printf("<html> ")
   printf("<title>sss.sh@cosol.jp</title> ")
   printf("<link href=\"data:image/x-icon;base64,AAABAAEAEBAAAAEAGABoAwAAFgAAACgAAAAQAAAAIAAAAAEAGAAAAAAAAAAAABMLAAATCwAAAAAAAAAAAAD////////////////////////////////////////////////////////////////6+/nP2Mrf5dvR2czZ39Pg5ty/y7fM1MW0watviF5rhVlsh1tkgFFtiFxlgFI/YCf19vPBzLrJ0sLCzbrK1MTM1caxvqnT2s6ru6BQbzpYdkRYdUNKajRWdEJUcT4sURL/////+fr99vX99vX/////+vze1ti+tL6gpqEiSAkPOgAfRwMXQAAWPwAXQAAbQwDP8+R73reG4b2G4b2D37qE37qG476D3rnD0s+lqqI7XCYROwAcRAAcRAAcRAAcRADs+vQxyowEvnMPwXkOwHgOwXgMv3cXxoG/4MuDk3DS1M9DYy8SPQAcRAAcRAAcRAD////R8+UhxYMYw30cxIAcxIAaw38kyYjB380dQQBuhl3R1s0oThEVPgAZQgAZQgD///////+m6M0PwXgbxIAcxIAaw38kyYjD4c8zUxYROwCjspmpuJ8aQggiSQciSQf///////////9p2KsOwHgcxIAaw38fxoLc9+rj597d49vj59/y8vLe5Nrf5dzg5dz////////////v+/Y7zJITwnsbxIAZwHy30cj////////////l5ebp6Ov////////////////////////N8uMcxIAXw30exIGyzcPt5+n8/Pz9/f3R0tPZ2dv///////////////////////////+Z5cYMwHcexYHg+u/6+Pn5+fnf4OHm5uf///////////////////////////////////9i1qgRwXrd9uv////////////////////////////////////////////////////r+vQ2y4/U9Of////////////////////////////////////////////////////////I8eDf9+3///////////////////////////////////////////////////////////////////////////////////////////8AAGljAAAKCQAACTwAAHk+AABtLgAAcGwAAHByAAB0LgAAZ2UAAHJtAAAuUAAAcmkAAHRhAABvbgAAa2UAAAoJ\" rel=icon type=image/x-icon/> ")
   printf("<style type=\"text/css\"> ")
   printf(".stdn {font-size: small;} ")
   printf(".stdn thead tr {background-color:#0466cb; color:#ffffff; white-space:nowrap} ")
   printf(".stdn tbody tr:nth-child(even) {background-color:#ffffc9;} ")
   printf(".stdn tbody tr:hover {background-color:#808080;} ")
   printf("body{padding-bottom:30px;} ")
   printf("* html body{overflow: hidden;}  ")
   printf("div#footer {position: fixed !important;position: absolute;bottom: 0;width: 100%;height: 12px;font-size: 11px;text-align: center;padding: 3px;background-color: #e7e7e7;color: #000;} ")
   printf("</style>")
}


#===========================================================
# Main - ss.awk
#-----------------------------------------------------------
BEGIN {
   FS=" "                                                   #Default - Field Separetor
   OFS=" "                                                  #Default - Output Field Separetor
   for(i=1;i<=255;i++) ASC[sprintf("%c",i)]=i               #ASCII char table
   #intialize variable
   _holder[0]="";delete _holder                             #holder info - dummy proc for handing as aray
   _waiter[0]="";delete _waiter                             #waiter info - dummy proc for handing as aray
   #config - behavior of output
   C_SEP=","                                                #delimiter character (ex.C_SEP=SUBSEP)
   C_PRINT_IN_PLACE_BLANK="_"                               #how to output blank(ex. [pmon timer]<-->[pmon_timer])
   C_OUTPUT_RESULT_WITH_BLANK="  "                          #not modify
   #COMMAND_TYPE/NAME(ref.v$sqlcommand)
   SQL_TYPE[0]  ="";               SQL_TYPE[20] ="DROP SYNONYM";        SQL_TYPE[40] ="ALTER TABLESPACE";   SQL_TYPE[60] ="ALTER TRIGGER";               SQL_TYPE[81] ="CREATE TYPE BODY";   SQL_TYPE[158]="DROP DIRECTORY";         SQL_TYPE[178]="DROP CONTEXT";         SQL_TYPE[198]="PURGE DBA RECYCLEBIN";       SQL_TYPE[219]="ALTER FLASHBACK ARCHIVE";
   SQL_TYPE[1]  ="CREATE TABLE";   SQL_TYPE[21] ="CREATE VIEW";         SQL_TYPE[41] ="DROP TABLESPACE";    SQL_TYPE[61] ="DROP TRIGGER";                SQL_TYPE[82] ="ALTER TYPE BODY";    SQL_TYPE[159]="CREATE LIBRARY";         SQL_TYPE[179]="ALTER OUTLINE";        SQL_TYPE[199]="PURGE TABLESPACE";           SQL_TYPE[220]="DROP FLASHBACK ARCHIVE";
   SQL_TYPE[2]  ="INSERT";         SQL_TYPE[22] ="DROP VIEW";           SQL_TYPE[42] ="ALTER SESSION";      SQL_TYPE[62] ="ANALYZE TABLE";               SQL_TYPE[83] ="DROP TYPE BODY";     SQL_TYPE[160]="CREATE JAVA";            SQL_TYPE[180]="CREATE OUTLINE";       SQL_TYPE[200]="PURGE TABLE";                SQL_TYPE[222]="CREATE SCHEMA SYNONYM";
   SQL_TYPE[3]  ="SELECT";         SQL_TYPE[23] ="VALIDATE INDEX";      SQL_TYPE[43] ="ALTER USER";         SQL_TYPE[63] ="ANALYZE INDEX";               SQL_TYPE[84] ="DROP LIBRARY";       SQL_TYPE[161]="ALTER JAVA";             SQL_TYPE[181]="DROP OUTLINE";         SQL_TYPE[201]="PURGE INDEX";                SQL_TYPE[224]="DROP SCHEMA SYNONYM";
   SQL_TYPE[4]  ="CREATE CLUSTER"; SQL_TYPE[24] ="CREATE PROCEDURE";    SQL_TYPE[44] ="COMMIT";             SQL_TYPE[64] ="ANALYZE CLUSTER";             SQL_TYPE[85] ="TRUNCATE TABLE";     SQL_TYPE[162]="DROP JAVA";              SQL_TYPE[182]="UPDATE INDEXES";       SQL_TYPE[202]="UNDROP OBJECT";              SQL_TYPE[225]="ALTER DATABASE LINK";
   SQL_TYPE[5]  ="ALTER CLUSTER";  SQL_TYPE[25] ="ALTER PROCEDURE";     SQL_TYPE[45] ="ROLLBACK";           SQL_TYPE[65] ="CREATE PROFILE";              SQL_TYPE[86] ="TRUNCATE CLUSTER";   SQL_TYPE[163]="CREATE OPERATOR";        SQL_TYPE[183]="ALTER OPERATOR";       SQL_TYPE[203]="DROP DATABASE";              SQL_TYPE[226]="CREATE PLUGGABLE DATABASE";
   SQL_TYPE[6]  ="UPDATE";         SQL_TYPE[26] ="LOCK TABLE";          SQL_TYPE[46] ="SAVEPOINT";          SQL_TYPE[66] ="DROP PROFILE";                SQL_TYPE[87] ="CREATE BITMAPFILE";  SQL_TYPE[164]="CREATE INDEXTYPE";       SQL_TYPE[184]="Do not use 184";       SQL_TYPE[204]="FLASHBACK DATABASE";         SQL_TYPE[227]="ALTER PLUGGABLE DATABASE";
   SQL_TYPE[7]  ="DELETE";         SQL_TYPE[27] ="NO-OP";               SQL_TYPE[47] ="PL/SQL EXECUTE";     SQL_TYPE[67] ="ALTER PROFILE";               SQL_TYPE[88] ="ALTER VIEW";         SQL_TYPE[165]="DROP INDEXTYPE";         SQL_TYPE[185]="Do not use 185";       SQL_TYPE[205]="FLASHBACK TABLE";            SQL_TYPE[228]="DROP PLUGGABLE DATABASE";
   SQL_TYPE[8]  ="DROP CLUSTER";   SQL_TYPE[28] ="RENAME";              SQL_TYPE[48] ="SET TRANSACTION";    SQL_TYPE[68] ="DROP PROCEDURE";              SQL_TYPE[89] ="DROP BITMAPFILE";    SQL_TYPE[166]="ALTER INDEXTYPE";        SQL_TYPE[186]="Do not use 186";       SQL_TYPE[206]="CREATE RESTORE POINT";       SQL_TYPE[229]="CREATE AUDIT POLICY";
   SQL_TYPE[9]  ="CREATE INDEX";   SQL_TYPE[29] ="COMMENT";             SQL_TYPE[49] ="ALTER SYSTEM";       SQL_TYPE[70] ="ALTER RESOURCE COST";         SQL_TYPE[90] ="SET CONSTRAINTS";    SQL_TYPE[167]="DROP OPERATOR";          SQL_TYPE[187]="CREATE SPFILE";        SQL_TYPE[207]="DROP RESTORE POINT";         SQL_TYPE[230]="ALTER AUDIT POLICY";
   SQL_TYPE[10] ="DROP INDEX";     SQL_TYPE[30] ="AUDIT OBJECT";        SQL_TYPE[50] ="EXPLAIN";            SQL_TYPE[71] ="CREATE MATERIALIZED VIEW LOG";SQL_TYPE[91] ="CREATE FUNCTION";    SQL_TYPE[168]="ASSOCIATE STATISTICS";   SQL_TYPE[188]="CREATE PFILE";         SQL_TYPE[209]="DECLARE REWRITE EQUIVALENCE";SQL_TYPE[231]="DROP AUDIT POLICY";
   SQL_TYPE[11] ="ALTER INDEX";    SQL_TYPE[31] ="NOAUDIT OBJECT";      SQL_TYPE[51] ="CREATE USER";        SQL_TYPE[72] ="ALTER MATERIALIZED VIEW LOG"; SQL_TYPE[92] ="ALTER FUNCTION";     SQL_TYPE[169]="DISASSOCIATE STATISTICS";SQL_TYPE[189]="UPSERT";               SQL_TYPE[210]="ALTER REWRITE EQUIVALENCE";  SQL_TYPE[238]="ADMINISTER KEY MANAGEMENT";
   SQL_TYPE[12] ="DROP TABLE";     SQL_TYPE[32] ="CREATE DATABASE LINK";SQL_TYPE[52] ="CREATE ROLE";        SQL_TYPE[73] ="DROP MATERIALIZED VIEW LOG";  SQL_TYPE[93] ="DROP FUNCTION";      SQL_TYPE[170]="CALL METHOD";            SQL_TYPE[190]="CHANGE PASSWORD";      SQL_TYPE[211]="DROP REWRITE EQUIVALENCE";   SQL_TYPE[239]="CREATE MATERIALIZED ZONEMAP";
   SQL_TYPE[13] ="CREATE SEQUENCE";SQL_TYPE[33] ="DROP DATABASE LINK";  SQL_TYPE[53] ="DROP USER";          SQL_TYPE[74] ="CREATE MATERIALIZED VIEW";    SQL_TYPE[94] ="CREATE PACKAGE";     SQL_TYPE[171]="CREATE SUMMARY";         SQL_TYPE[191]="UPDATE JOIN INDEX";    SQL_TYPE[212]="CREATE EDITION";             SQL_TYPE[240]="ALTER MATERIALIZED ZONEMAP";
   SQL_TYPE[14] ="ALTER SEQUENCE"; SQL_TYPE[34] ="CREATE DATABASE";     SQL_TYPE[54] ="DROP ROLE";          SQL_TYPE[75] ="ALTER MATERIALIZED VIEW";     SQL_TYPE[95] ="ALTER PACKAGE";      SQL_TYPE[172]="ALTER SUMMARY";          SQL_TYPE[192]="ALTER SYNONYM";        SQL_TYPE[213]="ALTER EDITION";              SQL_TYPE[241]="DROP MATERIALIZED ZONEMAP";
   SQL_TYPE[15] ="ALTER TABLE";    SQL_TYPE[35] ="ALTER DATABASE";      SQL_TYPE[55] ="SET ROLE";           SQL_TYPE[76] ="DROP MATERIALIZED VIEW";      SQL_TYPE[96] ="DROP PACKAGE";       SQL_TYPE[173]="DROP SUMMARY";           SQL_TYPE[193]="ALTER DISK GROUP";     SQL_TYPE[214]="DROP EDITION";
   SQL_TYPE[16] ="DROP SEQUENCE";  SQL_TYPE[36] ="CREATE ROLLBACK SEG"; SQL_TYPE[56] ="CREATE SCHEMA";      SQL_TYPE[77] ="CREATE TYPE";                 SQL_TYPE[97] ="CREATE PACKAGE BODY";SQL_TYPE[174]="CREATE DIMENSION";       SQL_TYPE[194]="CREATE DISK GROUP";    SQL_TYPE[215]="DROP ASSEMBLY";
   SQL_TYPE[17] ="GRANT OBJECT";   SQL_TYPE[37] ="ALTER ROLLBACK SEG";  SQL_TYPE[57] ="CREATE CONTROL FILE";SQL_TYPE[78] ="DROP TYPE";                   SQL_TYPE[98] ="ALTER PACKAGE BODY"; SQL_TYPE[175]="ALTER DIMENSION";        SQL_TYPE[195]="DROP DISK GROUP";      SQL_TYPE[216]="CREATE ASSEMBLY";
   SQL_TYPE[18] ="REVOKE OBJECT";  SQL_TYPE[38] ="DROP ROLLBACK SEG";   SQL_TYPE[58] ="ALTER TRACING";      SQL_TYPE[79] ="ALTER ROLE";                  SQL_TYPE[99] ="DROP PACKAGE BODY";  SQL_TYPE[176]="DROP DIMENSION";         SQL_TYPE[196]="ALTER LIBRARY";        SQL_TYPE[217]="ALTER ASSEMBLY";
   SQL_TYPE[19] ="CREATE SYNONYM"; SQL_TYPE[39] ="CREATE TABLESPACE";   SQL_TYPE[59] ="CREATE TRIGGER";     SQL_TYPE[80] ="ALTER TYPE";                  SQL_TYPE[157]="CREATE DIRECTORY";   SQL_TYPE[177]="CREATE CONTEXT";         SQL_TYPE[197]="PURGE USER RECYCLEBIN";SQL_TYPE[218]="CREATE FLASHBACK ARCHIVE";
   #ENQUEUE MODE(PL/SQL Package Procedure,... DBMS_LOCK    |NUL|SS|SX|S|SSX|X|
   ENQ_MODE[NULL]=1; ENQ_VAL[1]="Null" #null               | o |o |o |o| o |o|
   ENQ_MODE[SS]  =2; ENQ_VAL[2]="SS"   #sub share          | o |o |o |o| o | |GyouKyouyu
   ENQ_MODE[SX]  =3; ENQ_VAL[3]="SX"   #sub exclusive      | o |o |o | |   | |GyouHaita
   ENQ_MODE[S]   =4; ENQ_VAL[4]="S"    #share              | o |o |  |o|   | |Kyouyu
   ENQ_MODE[SSX] =5; ENQ_VAL[5]="SSX"  #share/sub exclusive| o |o |  | |   | |GyoKyouyuHaita
   ENQ_MODE[X]   =6; ENQ_VAL[6]="X"    #exclusive          | o |  |  | |   | |Haita
   #extend proc - hungchk
   if(ep=="hungchk"){
      FS=","
      split("pid,addr,saddr,image,seq,event",key,",")       #items for evaluating hang
      keyLen=length(key)
   }
   if(rtype==""){
      rtype="text"
   }else if(rtype=="html"){
      OutputHeadCssScript()
   }
}

#===========================================================
#about release version
# Oracle9i Enterprise Edition Release 9.2.0.8.0 - Production
# Oracle Database 10g Enterprise Edition Release 10.1.0.5.0 - Production
# Oracle Database 10g Enterprise Edition Release 10.2.0.5.0 - Production
# Oracle Database 11g Enterprise Edition Release 11.1.0.7.0 - Production
# Oracle Database 11g Enterprise Edition Release 11.2.0.4.0 - Production
# Oracle Database 12c Enterprise Edition Release 12.1.0.2.0 - 64bit Production
#-----------------------------------------------------------
_inss==0 && $0~"^Oracle.*Release" {
   _psr=int(Remove(MID($0,"Release "," "),"\\."))
   _ver=int(_psr/1000)
}

#===========================================================
#get recent timestamp
#-----------------------------------------------------------
_inss==0 && $0~"^\\*\\*\\* [12][0-9]*-[0-9]*-[0-9]* [0-9]*:.*:"{
   _ts=$2 " " $3                                            #set TimeStamp
   next
}

#===========================================================
#start piont of SYSTEMSTATE
#-----------------------------------------------------------
_inss==0 && $0!~"^SYSTEM STATE" {next}                      #not do processing if out range systemstate
/^END OF SYSTEM STATE/              {_inss=0;next}          #out range systemstate
/^PSEUDO PROCESS for group/         {_inss=0;next}          #out range systemstate

/^SYSTEM STATE/{                                            #start point of systemstate
   _sc++                                                    #increment number of systemstate
   _s[_sc,"title"]=Trim($0)                                 #output title
   _s[_sc,"ts"]=_ts                                         #set recent timestamp
   _s[_sc,"fn"]=FILENAME                                    #set target trace-file-name
   _c2=0                                                    #initialize number of processes
   _soc=0                                                   #initialize StateObjectCount(use in sstree)
   _inss=1                                                  #(in)range SystemState
   printf("\nNow Analyzing %s %s\n",Trim($0),_ts) > "/dev/stderr" #progress title
   next
}

#===========================================================
#extend proc - sstree
#-----------------------------------------------------------
ep=="sstree" && $0~"SO:.*, owner: " {
   _so[_sc,"count"]=++_soc
   _cso=Remove(MID($0,"SO: ",","),"0x0*")
   _cowner=Remove(MID($0,"owner: ",","),"0x0*")
   _ctype=Remove(MID($0,"type: ",","),"0x0*")
   _so[_sc,_soc]   =_cso
   _so[_sc,_cso,"owner"]=_cowner
   _so[_sc,_cso,"type"] =_ctype
   if(_cowner=="") _so[_sc,_cso,"depth"]=0
   else            _so[_sc,_cso,"depth"]=_so[_sc,_cowner,"depth"]+1
   getline
   _so[_sc,_cso,"name"] =MID($0,"name=",",")
   next
}

#===========================================================
#PROCESS
#-----------------------------------------------------------
/^PROCESS [0-9]+/{
   _c2++                                                    #increment number of processes
   _s[_sc,"pcnt"]=_c2                                       #initialize number of processes
   _pid=Remove($2,":")                                      #v$process.pid(alias)
   _2[_sc,_c2,"pid"]=_pid                                   #v$process.pid
   if(_ver>=112) _2[_sc,_c2,"image"]=Remove($0,".*: ")
   _c4=0                                                    #initialize number of sessions
   if(_c2%60==0) printf("\n")                               #output newline every time analyzing 60 processes
   printf(".")  > "/dev/stderr"                             #output progress
   getline
   getline
   _2[_sc,_c2,"addr"]=Remove(MID($0,"SO: ",","),"0x0*")
   while($0!~"latch info") getline
   while($0!~"O/S info"){
      getline
      if($0~"^ +holding"){AddRes(_holder,_sc,_pid,$3,"latch","","")}
      if($0~"^ +waiting"){AddRes(_waiter,_sc,_pid,$3,"latch","","")}
   }
   _2[_sc,_c2,"user"]=Remove($4,",")                        #v$process.username
   _2[_sc,_c2,"term"]=Remove($6,",")                        #v$process.terminal
   _2[_sc,_c2,"ospid"]=$8                                   #v$process.spid
   getline
   if(_psr<112020) _2[_sc,_c2,"image"]=Remove($0,"^.*image: ") #v$process.program
   _cevt=""                                                 #initialize Current EVenT
}

#===========================================================
#SESSION
#-----------------------------------------------------------
/SO: .*, type: 4,/{
   _cevt=""                                                 #initialize Current EVenT
   so=Remove(MID($0,"SO: ",","),"0x0*")
   
   tmp=""
   tmp_wait_time=""
   tmp_block=""
   tmp_block_sess=""
   tmp_cinfo=""
   
   #fix - v1.0.0b3
   #in each psr, there is difference in output specification.
   #The difference is too complicated to check the value of each SessSO's items while read line by line.
   #I have designed a process as follows.
   #  1) set the all line that we want to check to only one tmp variable.
   #  2) get the necessary value from tmp variable(using the MID-function
   while(getline > 0){
      #out-of-range, break while loop
      if($0~"last wait for"               ) break           #9.2.0.x  - 10.2.0.5
      if($0~"Dumping Session Wait History"){                #10.1.0.x - 11.1.0.6
         getline;wait_hist=$0                               #about wait time,we cannot see with systemstate until 10.2
         getline;wait_hist=sprintf("%s %s ",wait_hist,$0)   #cf. Wait History
         break
      }
      if($0~"Session Wait History:"       ) break           #11.1.0.7 - 
      if($0~"Wait State:"                 ) break           #11.1.0.6 - 
      if($0~"Sampled Session History"     ) break           #11.1.0.7 - 
      if($0~"temporary object counter:"   ) break           #9.2.0.x  - 
      #there is several SessSO's items, easy to check the value while read line by line.
      if($0~"client info: ") tmp_cinfo=Remove($0,".*info: ")
      if($0~"wait times.*total=") tmp_wait_time=Remove($0,".*total=")
      if($0~"Dumping.*blocker"){getline; tmp_block_sess=sprintf("sid:%s/ser:%s@inst:%s",Remove($4,","),Remove($6,","),Remove($2,","))}
      #evaluation of the sess state obj I set on a single line in the tmp variable
      tmp=sprintf("%s %s ",tmp,$0)                          #use single-byte space extraction processing of format part end
   }
   if(_psr>=102040 && _psr!=111060 && tmp!~"service name") next #10.2.0.4- or 11.1.0.7-, there is no output "service name", do next
   _c4++                                                    #this line later, set the value of Sess SO to the array(increment var for number of session
   _2[_sc,_c2,"sess cnt"]=_c4                               #set process's session count
   _4[_sc,"so4",so]=_c4                                    
   
   _4[_sc,_c2,_c4,"saddr"]=so
   sid=MID(tmp,"sid: "," ")
   _4[_sc,_c2,_c4,"sid"]=sid                                #v$session.sid
   _4[_sc,"sid",sid]=sprintf("%s,%s",_c2,_c4)               #(may not use) search key for _c2(proc count),_c4(sess count) from sid
   _4[_sc,_c2,_c4,"ser"]=MID(tmp,"ser: "," ")               #v$session.serial#
   _4[_sc,_c2,_c4,"service"]=MID(tmp,"service name: "," ")  #v$session.service_name
   _4[_sc,_c2,_c4,"command"]=SQL_TYPE[MID(tmp,"oct: ",",")] #v$session.command
   username=MID(tmp,", user: "," ")                         # - 11.2.0.4
   if(username=="") username=MID(tmp,"user#/name: "," ")    #12.1.0.1 - 
   username=Remove(username,".*/")
   _4[_sc,_c2,_c4,"username"]=username                      #v$session.username
   sql_addr=Remove(MID(tmp," sql: ",","),"0x0*")
   if(sql_addr!="(nil)") _4[_sc,_c2,_c4,"sql_addr"]=sql_addr #v$session.sql_address
   _4[_sc,_c2,_c4,"osuser"]=MID(tmp,"info: user: ",",")     #v$session.osuser
   _4[_sc,_c2,_c4,"term"]=MID(tmp,"term: ",",")             #v$session.terminal
   _4[_sc,_c2,_c4,"process"]=Remove(MID(tmp,"ospid: "," "),",") #v$session.process
   _4[_sc,_c2,_c4,"machine"]=MID(tmp,"machine: "," ")       #v$session.machine
   _4[_sc,_c2,_c4,"program"]=MID(tmp,"program: "," ")       #v$session.program
   _4[_sc,_c2,_c4,"cli_info"]=tmp_cinfo
   _4[_sc,_c2,_c4,"module"]=MID(tmp,"ation name: ",", hash")
   _4[_sc,_c2,_c4,"action"]=MID(tmp,"ction name: ",", hash")
   _cevt=MID(tmp,"waiting for '","'")
   _4[_sc,_c2,_c4,"event"]=_cevt                            #v$session.event(alias)
   wait_time=Remove(MID(tmp,"wait_time="," "),",")
   if(wait_time=="") wait_time=tmp_wait_time
   if(wait_time==0 && _ver~"10"){                           #about wait time,we cannot see with systemstate until 10.2
      if(wait_hist~_cevt){                                  #if same value current-event/wait-history
         wait_time=MID(wait_hist,"wait_time="," ")          #get value from Wait History
         if(_psr!=102050) wait_time=wait_time/1000000       #Except 10g AND 10.2.0.5 , convert usec to sec
      }
   }
   if(_psr==111060) wait_time=wait_time/1000000
   _4[_sc,_c2,_c4,"wait_time"]=wait_time                    #v$session.wait_time
   seq=MID(tmp," seq="," ")                                 # - 10.2.0.5
   if(seq=="") seq=MID(tmp," seq_num="," ")                 #11.1.0.6 - 
   _4[_sc,_c2,_c4,"seq"]=seq                                #v$session.seq#
   block_sess=Remove(Remove(MID(tmp,"blocking sess="," "),"0x"),"^0+")# - 10.2.0.5
   if(block_sess=="(nil)") block_sess=""
   else if(block_sess=="") block_sess=tmp_block_sess
   _4[_sc,_c2,_c4,"block_sess"]=block_sess                  #v$blocking_session
   if((_ver=="92" && _cevt=="enqueue") || _cevt~"DFS lock handle"){
      p1=GetNameAndType(MID(tmp,"name|mode=",","))
      _cevt=sprintf("%s(%s)",_cevt,p1)
      _4[_sc,_c2,_c4,"event"]=_cevt
   }
   next
}

#===========================================================
#enqueue
#-----------------------------------------------------------
/\(enqueue\) <no resource>/{next}
/\(enqueue\) released/{next}
/\(enqueue\) ..-.*-/{
   tmp=$2
   getline;getline;
   mode=Remove($2,",")
   if($0~"mode: " && $0~"req: "){                           #linked converter-Q
      _cevt= _cevt "(conversion)"
      if($0~"req: ")  AddRes(_waiter,_sc,_pid,tmp,"enqueue",mode,_cevt)
      #if($0~"mode: ") AddRes(_holder,_sc,_pid,tmp,"enqueue",_cevt) #noise(enq converter-Q)
   }else{
      if($0~"mode: ") AddRes(_holder,_sc,_pid,tmp,"enqueue",mode,_cevt)
      if($0~"req: ")  AddRes(_waiter,_sc,_pid,tmp,"enqueue",mode,_cevt)
   }
   next
}

#===========================================================
#mutex
#-----------------------------------------------------------
/ +Mutex .* idn.*NONE/{next}
/ +Mutex .* idn /{
   id=MID($0,"idn "," ")
   sid=MID($0,"(",",")
   if(sid~"nil") sid=MID($0,"nil)(",",")                    #noise(tc_mts_l11204.trc@line:9814)
   if(sid!=0 && $NF!~"NONE"){
      mode=Remove($NF,"\\(.*")
      getline
      #prev version 1.0.1
      #   uid=MID($0," uid "," ")
      #   if(sid==uid) AddRes(_holder,_sc,_pid,id,"mutex",_cevt)
      #   else         AddRes(_waiter,_sc,_pid,id,"mutex",_cevt)
      if(mode~"GET") AddRes(_waiter,_sc,_pid,id,"mutex",mode,_cevt)
      else           AddRes(_holder,_sc,_pid,id,"mutex",mode,_cevt)
   }
   next
}
#===========================================================
#row cache enqueue
#-----------------------------------------------------------
/ +row cache enqueue:.*(mode|req)/{
   tmp=$NF
   mode=ElemN($NF,"=",2)
   getline;getline
   if(_ver<=112) addr=Remove(MID($0,"address="," "),"0x")   #<=11gR2
   if(_ver>=121) addr=Remove(MID($0,"addr="," "),"0x")      #>=12cR1
   addr=Remove(addr,"^0+")
   
   if(_ver<=112) id=sprintf("%s[%s]",addr,$NF)                       #<=11gR2
   if(_ver>=121) id=sprintf("%s[%s %s %s]",addr,$(NF-2),$(NF-1),$NF) #>=12cR1 - set cid info
   
   if(tmp~"mode") AddRes(_holder,_sc,_pid,id,"rcache",mode,_cevt)
   if(tmp~"req")  AddRes(_waiter,_sc,_pid,id,"rcache",mode,_cevt)
   next
}

#===========================================================
#LibraryObjectLock
#-----------------------------------------------------------
/LIBRARY OBJECT LOCK:/{                                     #<=11gR1
   id=Remove(MID($0,"handle="," "),"0x0*")
   mode=ElemN($NF,"=",2); if(mode=="N") next
   if($0~"req")       AddRes(_waiter,_sc,_pid,id,"lock",mode,_cevt)
   else if($0~"mode") AddRes(_holder,_sc,_pid,id,"lock",mode,_cevt)
}

/LibraryObjectLock:/{                                       #>=11gR2
   id=Remove($3,".*=0x0*")
   mode=ElemN($NF,"=",2); if(mode=="N") next
   if($4~"Req")       AddRes(_waiter,_sc,_pid,id,"lock",mode,_cevt)
   else if($4~"Mode") AddRes(_holder,_sc,_pid,id,"lock",mode,_cevt)
}

#===========================================================
#LibraryObjecPin
#-----------------------------------------------------------
/LIBRARY OBJECT PIN:/{                                      #<=11gR1
   id=Remove(MID($0,"handle="," "),"0x0*")
   mode=ElemN($NF,"=",2); if(mode=="N") next
   if($0~"req")  AddRes(_waiter,_sc,_pid,id,"pin",_cevt)
   if($0~"mode") AddRes(_holder,_sc,_pid,id,"pin",_cevt)
}
/LibraryObjectPin:/{                                        #>=11gR2
   id=Remove($3,".*=0x0*")
   mode=ElemN($NF,"=",2); if(mode=="N") next
   if($0~"Req")       AddRes(_waiter,_sc,_pid,id,"pin",mode,_cevt)
   else if($0~"Mode") AddRes(_holder,_sc,_pid,id,"pin",mode,_cevt)
}

#===========================================================
#Analyze Running SQL
#-----------------------------------------------------------
/LIBRARY.*HANDLE:|LibraryHandle:/{
   if(!analyze_sql) next
   if($0!~sql_addr) next
   getline;sql=MID($0,"=")
   getline
   while($1!~"hash=" && $1!~"FullHashValue="){
      sql=sprintf("%s %s",sql,$0)
      getline
   }
   _sql[sql_addr]=sql
}

#===========================================================
#output report
#-----------------------------------------------------------
END{
   if(ep~"sstree"){
      #---extend proc(StateObjectTree)
      printf("\n%s%s\n%s%s\n",tmp,"state object tree",tmp,Repeat("~",17)) #title
      soc=_so[i,"count"]
      for(j=1;j<=soc;j++){
         so=_so[i,j]
         dep=Repeat("  ",_so[i,so,"depth"])
         name=Replace(_so[i,so,"name"]," ","_")
         printf("%s%s %s %s\n",dep,so,_so[so,"type"],name)
      }
      exit
   }
   #========================================================
   #initialize(1/2)
   #--------------------------------------------------------
   #--proc/sess stat
   
   e2[0]=""; delete e2                                      #process state         - dummy proc for handing as aray
   f2[0]=""; delete f2                                      #process state(format) - dummy proc for handing as aray
   e4[0]=""; delete e4                                      #session state         - dummy proc for handing as aray
   f4[0]=""; delete f4                                      #session state(format) - dummy proc for handing as aray
   SetProcSessElem()                                        #set proc/sess-state's element
   en2=length(e2)                                           #Element of number proc state
   en4=length(e4)                                           #Element of number sess state
   en24=en2+en4
   for(i=1;i<=en2;i++) e24[i]  =e2[i];     for(i=1;i<=en4;i++) e24[i+en2]  =e4[i]     #set proc/sess state element
   for(i=1;i<=en2;i++) f24[i]=Trim(f2[i]); for(i=1;i<=en4;i++) f24[i+en2]=Trim(f4[i]) #set is number proc/sess state
   #--waiter/holder
   split("type,id,pid,mode,event",eW,",")                   #element waiter
   split("-   ,- ,   ,-   ,-    ",fW,",")                   #is number waiter(-:str, N/A:num
   split("pid,mode,event",eH,",")                           #element holder
   split("   ,-   ,-    ",fH,",")                           #is number holder(-:str, N/A:num
   enW=length(eW)                                           #Element of number waiter
   enH=length(eH)                                           #Element of number holder
   enWH=enW+enH
   for(i=1;i<=enW;i++) eWH[i]=eW[i]          ; for(i=1;i<=enH;i++) eWH[i+enW]=eH[i]
   for(i=1;i<=enW;i++) fWH[i]=Trim(fW[i]); for(i=1;i<=enH;i++) fWH[i+enW]=Trim(fH[i])
   #========================================================
   #set the analysis content to the output array variable
   #--------------------------------------------------------
   for(i=1;i<=_sc;i++){
      #---proc/sess state
      n2=_s[i,"pcnt"]                                       #set number of processes
      r=1                                                   #initialize line-number(for array variable)
      for(j=1;j<=n2;j++){
         n4=_2[i,j,"sess cnt"]                              #get proc-stat's sess-state count
         for(k=1;k<=n4;k++)                                 #if sess-stat's count >= 2
            for(l=1;l<=en4;l++)
               d24[i,r+k-1,l+en2]=_4[i,j,k,e4[l]]           #set sess-state's each element
         for(k=0;k<=(n4==0?0:n4-1);k++)                     #set proc-state even proc-state's sess-state is none, 
            for(l=1;l<=en2;l++) d24[i,r+k,l]=_2[i,j,e2[l]]  #set proc-state's each element
         r=(n4==0?++r:r+n4)                                 #set next line-number
      }
      for(j=1;j<r;j++)
         
      rn24[i]=r
      #---waiter/holder
      nw=_waiter[i,"cnt"]                                   #set waiter's number of rows
      r=prev=1                                              #r:current-line(increment when holder is evalueated),prev:current line of the previous evaluation
      for(j=1;j<=nw;j++){                                   #j : loop waiter's number of rows
         nh=_holder[i,"cnt"]                                #get holder's number of rows
         for(k=1;k<=nh;k++)                                 #k : loop holder's number of rows
            if(_waiter[i,j,"id"]==_holder[i,k,"id"] &&      #same value waiter/holder's id AND
               _waiter[i,j,"type"]==_holder[i,k,"type"]){   #same value waiter/holder's lock-type(such as enq,latch,rcahce,...)
               for(l=1;l<=enH;l++)                          #set holder info
                  dWH[i,r,l+enW]=_holder[i,k,eH[l]]
               r++
            }
         for(k=prev;k<=(r==prev?prev:r-1);k++)              #(r==prev?prev:r-1) 
            for(l=1;l<=enW;l++)                             #set waiter info
               dWH[i,k,l]=_waiter[i,j,eW[l]];
         if(r==prev) r++;prev=r                             #if could not detect holder, increment current-line
      }
      rnWH[i]=r
   }
   #========================================================
   #output
   #--------------------------------------------------------
   if(rtype=="text"){
      OutputTextReport()
   }if(rtype=="html"){
      OutputHtmlReport()
   }
}
EOF
   return 0
}

#===========================================================
# awk script - summary of ss.awk
#-----------------------------------------------------------
function ShowAwkSsSumProcSess ()
{
cat << \EOF
/^ +pid/{                                                   #If $0 is "pid",
   for(i=1;i<=NF;i++)                                       #search for all elements of the output lines
      for(j=1;j<=keyLen;j++)                                #Further explore all the elements of the key array,  and set whether the elements of the 
         if(Trim($(i))==key[j])                             #key array is what number at the output of the ss.awk to keyPos
            keyPos[j]=i
   #for(j=1;j<=keyLen;j++){print keyPos[j]}                 #test code
   while(getline > 0){
      if(Trim($1)=="---"){c++;if(c%2==0) break;continue}    #Continue and if the evaluation in the first element is "---", outside if the break
      print $0
   }
}
EOF
}


#===========================================================
# ShowUsage
#-----------------------------------------------------------
function ShowUsage(){
   echo -e "
  usage: ./sss.sh [systemstate-file [level=###] | -h | --help ]\n
  level   1: create html report
  level   2: analyze the running sql\n"
  ShowCopyright
}

#===========================================================
# SetOption
# p1: v_level(cmd-line arg)
#-----------------------------------------------------------
function SetOption(){
   eval `echo "obase=2; ibase=10; $1" | bc | rev | awk '{
      print("v_err_msg=\"\"")                               #initialize
      split($1,arr,"")                                      #set the binary desc of level to the arr
      split("0011",inv,"")                                  #set the binary desc of invalid level to the arr
      #    1:1          :create html report
      #    2:01         :analyze the running sql
      #    4:001        :summary of each element of the Proc/Sess SO
      #    8:0001       :invalid level(version 2.0.0
      for(i=1;i<=length($1) ;i++)
         if(arr[i] && inv[i]){
            printf("v_err_msg=\"invalid level : %s\"\n",2**(i-1))
            exit
         }else if(arr[i])
            printf("v_level%s=1\n",2**(i-1))
   }'`
}

#===========================================================
# GetArg
#-----------------------------------------------------------
argstr=`for arg in $@ ; do echo -n "${arg} " ; done`
function ArgList(){ echo ${argstr} | sed -e 's/ *= */=/g' | perl -pe 's/ +/\n/g' ; }
function GetArg(){ ArgList | grep "${1}=" | awk -F= '{print $2}' ; }


#===========================================================
# Check Args
#-----------------------------------------------------------

if [ "$1" == "-h" -o "$1" == "--help" ]; then
   ShowUsage
   exit
fi
if [ $# -eq 0 ]; then                                       #if specified file is not exist
   echo -e "\nspecify the file that contains  systemstate\n" #show message
   ShowUsage
   exit                                                     #exit shell
fi
if [ ! -e $1 ]; then                                        #if specified file is not exist
   echo -e "\nspecified file:{$1} is not exist\n"           #show message
   exit                                                     #exit shell
fi
if [ $# -ge 3 ]; then                                       #if "$# >= 3"
   echo -e "\ninvalid arguments"                            #show message
   ShowUsage                                                #show usage
   exit                                                     #exit shell
fi
v_level=`GetArg "level"`                                    #get cmd-line arg "level"
if [ $# -eq 2 -a "${v_level}" == "" ]; then                 #if "$#==2" AND arg "level" is not specified
   echo -e "\ninvalid arguments"                            #show message
   ShowUsage                                                #show usage
   exit                                                     #exit shell
fi

#===========================================================
# main
#-----------------------------------------------------------

#initialize option variable(for ss.awk
v_level1=""                                                 #is html report
v_level2=""                                                 #is analyze runinnng the sql
v_opt=""                                                    #for ss.awk option variable

# SetOption function verify cmd-line arg whether above option is enabled or not.
# and, set 1 to variable for each level("v_level<num>") if it is enabled.
SetOption ${v_level}
if [ "${v_err_msg}" != "" ]; then                           #if error message is not empty
   echo -e "\n${v_err_msg}"                                 #show message
   ShowUsage                                                #show usage
   exit                                                     #exit shell
fi

[ "${v_level1}" == "1" ] && v_opt="-v rtype=html"
[ "${v_level2}" == "1" ] && v_opt="${v_opt} -v analyze_sql=1"

fname1=`mktemp sstemp.XXXXXX`                               #for awk script file
ShowAwkCommonFunction > ${fname1}                           #create awk common function file
ShowAwkSs            >> ${fname1}                           #create ss.awk file
awk -f ${fname1} ${v_opt} $1                                #execute ss.awk

rm -rf ${fname1}                                            #remove tempolary ss.awk file

