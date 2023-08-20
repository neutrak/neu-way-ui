#!/usr/bin/env python3

#this takes as input two lines
#these lines checked for differences and the output is the detected difference

#whether or not to use color when making visual differences
#the runtime block at the end of this file gets color capabilities from TERMCAP environment variable
#use_color=True
use_color=False

ins_color='\033[32m'
del_color='\033[31m'
sub_color='\033[33m'

end_color='\033[0m'

#return a string of the given value
#forward-padded with pad characters until it is the required length
def strpad(val,length,pad):
    s=str(val)
    while(len(s)<length):
        s=pad+s
    return s

#a quick difference calculation; this is based on the levenshtein distance
#but is a faster implementation and stores more information
def quick_diff(start_line,end_line,debug=True):
    #edit distances between each substring pair
    dist=[]
    for i in range(0,len(start_line)+1):
        dist.append([])
        for i in range(0,len(end_line)+1):
            dist[-1].append(0)
    
    #dist is now a len(start_line) by len(end_line) 2d array
    
    #source string -> empty string by delete
    #on each character in source
    for i in range(0,len(start_line)+1):
        dist[i][0]=i
    
    #empty string -> dest string by insert
    #on each character in dest
    for j in range(0,len(end_line)+1):
        dist[0][j]=j
    
    #for each character in target string
    for j in range(1,len(end_line)+1):
        #for each character in source string
        for i in range(1,len(start_line)+1):
#            if(debug):
#                print('j='+str(j)+', i='+str(i)+', dist[i][j]='+str(dist[i][j]))
            
            #there was a character match
            #so there is no edit distance here
            if(start_line[i-1]==end_line[j-1]):
                #keep edit distance from last entry
                dist[i][j]=dist[i-1][j-1]
            else:
                dist[i][j]=min(
                    dist[i-1][j-1]+1,   #sub
                    dist[i-1][j]+1,     #del
                    dist[i][j-1]+1      #ins
                    )
    
    if(debug):
        print('dist:')
        
        sys.stdout.write('   ')
        for j in range(0,len(end_line)):
            if(j!=0):
                sys.stdout.write(',  ')
            sys.stdout.write(end_line[j])
        print('')
        
        for i in range(0,len(start_line)+1):
            if(i<len(start_line)):
                sys.stdout.write(start_line[i]+' ')
            else:
                sys.stdout.write('  ')
            for j in range(0,len(end_line)+1):
                if(j!=0):
                    sys.stdout.write(', ')
                sys.stdout.write(strpad(dist[i][j],2,'0'))
            print('')
        print('')
    
    #the version of this algorithm that's commonly documented seems to have a bug
    #namely, it never checks the value of the last character in the string
    #this means it considers "abcde" and "abcdf" to have an edit distance of 0, instead of 1
#    return (dist[len(start_line)-1][len(end_line)-1],dist)
    
    #I have therefore extended the array to consider the last character
    #this seems to work although I haven't formally verified it
    return (dist[len(start_line)][len(end_line)],dist)

#get the operations to transform start_line into end_line
def diff_ops(start_line,end_line,debug=True):
    diff_cnt,dist=quick_diff(start_line,end_line,debug=False)
    
    #all the operations necessary to transform start_line into end_line
    op_queue=[]
    
    row=len(dist)-1
    col=len(dist[-1])-1
    
    while(row>0 or col>0):
#        if(debug):
#            print('row='+str(row)+', col='+str(col))
        
        #if we have a length difference,
        #then handle that
        
        #out of start string characters
        if(row<=0):
            #insert
            op_queue.append(['ins',str(end_line[col-1])])
            col-=1
            continue
        #out of end string characters
        elif(col<=0):
            #delete
            op_queue.append(['del',str(start_line[row-1])])
            row-=1
            continue
        
        #equal characters require no operation
        if(start_line[row-1]==end_line[col-1]):
            op_queue.append(['nop',str(start_line[row-1])])
            #move diagonally up and back in the table
            row-=1
            col-=1
        else:
            sub_cost=dist[row-1][col-1]
            del_cost=dist[row-1][col]
            ins_cost=dist[row][col-1]
            
            min_cost=min(sub_cost,ins_cost,del_cost)
            
            #do a deletion
            if(min_cost==del_cost):
                op_queue.append(['del',str(start_line[row-1])])
                row-=1
            #do a substitution
            elif(min_cost==sub_cost):
                op_queue.append(['sub',str(start_line[row-1]),str(end_line[col-1])])
                row-=1
                col-=1
            #do an insertion
            elif(min_cost==ins_cost):
                op_queue.append(['ins',str(end_line[col-1])])
                col-=1

    
    #reverse so we go from first letter to last
    op_queue.reverse()
    
    op_cnt=0
    for i in range(0,len(op_queue)):
        if(not op_queue[i][0]=='nop'):
            op_cnt+=1
    
    if(debug):
        print(str(op_queue)+'; '+str(op_cnt)+' operations (excluding nops)')
    
    #assert that the number of operations we actually need to perform
    #is equal to the previously-calculated edit distance
    assert(op_cnt==diff_cnt)
    
    return (op_queue,op_cnt)

#gets a visual difference between strings based on the given operation queue
#op_queue is calculated from diff_ops
def visual_diff(op_queue,by_line=False,use_color=False):
    #get global color strings
    global del_color
    global ins_color
    global sub_color
    global end_color
    
    #transformations and metadata about them
    start_trans=''
    diff_str=''
    end_trans=''
    
    if(by_line):
        start_trans=[]
        diff_str=[]
        end_trans=[]
    
    #for each operation
    for op in op_queue:
        #a nop has the same letter for each string
        if(op[0]=='nop'):
            if(by_line):
                diff_str.append('')
                start_trans.append(op[1])
                end_trans.append(op[1])
            else:
                diff_str+=' '
                start_trans+=op[1]
                end_trans+=op[1]
        #a sub is different in start and end
        #this has two associated letters for that reason
        elif(op[0]=='sub'):
            if(by_line):
                diff_str.append('+/-')
                start_trans.append(op[1])
                end_trans.append(op[2])
            else:
                if(use_color):
                    diff_str+=sub_color+'X'+end_color
                else:
                    diff_str+='X'
                
                start_trans+=op[1]
                end_trans+=op[2]
        #a del existed in the start string but doesn't in the end
        elif(op[0]=='del'):
            if(by_line):
                diff_str.append('-')
                start_trans.append(op[1])
                end_trans.append('')
            else:
                if(use_color):
                    diff_str+=del_color+'-'+end_color
                else:
                    diff_str+='-'
                
                start_trans+=op[1]
                end_trans+=' '
        #an ins exists in the end string but didn't in the start
        elif(op[0]=='ins'):
            if(by_line):
                diff_str.append('+')
                start_trans.append('')
                end_trans.append(op[1])
            else:
                if(use_color):
                    diff_str+=ins_color+'+'+end_color
                else:
                    diff_str+='+'
                
                start_trans+=' '
                end_trans+=op[1]
        else:
            print('Error: Unknown Operation '+str(op[0]))
    
    return (start_trans,diff_str,end_trans)

def visual_line_diff(start_trans,diff_trans,end_trans,digits,idx,show_nops,show_ln_diff,output_cntxt,use_color=False):
    #get global color strings
    global del_color
    global ins_color
    global sub_color
    global end_color
    
    del_str='-'
    ins_str='+'
    sub_str='X'
    if(use_color):
        del_str=del_color+'-'+end_color
        ins_str=ins_color+'+'+end_color
        sub_str=sub_color+'X'+end_color
    
    out_str='diff idx '+str(('%'+str(digits)+'i') % (idx+1))+': '
    if(diff_trans==''):
        if(show_nops):
            out_str+='  '+start_trans
        else:
            return ''
    elif(diff_trans=='-'):
        out_str+=del_str+' '+start_trans
    elif(diff_trans=='+'):
        out_str+=ins_str+' '+end_trans
    elif(diff_trans=='+/-'):
        offset=len(out_str)
        
        #show intra-line differences if asked
        #note this is ONLY done on substituted lines
        if(show_ln_diff):
            ln_start_trans,ln_diff_str,ln_end_trans=visual_diff(diff_ops(start_trans,end_trans,debug=False)[0],by_line=False,use_color=use_color)
            #TODO: display tabs with 4 or 8 space widths, and substitute in the ln_diff_str to make alignment work
            #swap tabs for a placeholder so everything lines up right
            ln_start_trans=ln_start_trans.replace("\t",' ')
            ln_end_trans=ln_end_trans.replace("\t",' ')
            out_str+=del_str+' '+ln_start_trans+"\n"
            
            for j in range(0,offset-2):
                out_str+=' '
            out_str+=':   '
            out_str+=ln_diff_str+"\n"
            
            for j in range(0,offset-2):
                out_str+=' '
            out_str+=': '+ins_str+' '
            out_str+=ln_end_trans
        else:
            out_str+=del_str+' '+start_trans+"\n"
            for j in range(0,offset-2):
                out_str+=' '
            out_str+=': '
            out_str+=ins_str+' '+end_trans
        
    else:
        return 'Error: Unknown transformation '+diff_trans
    
    #if lines were skipped, then output an indicator of that
    last_line=0
    if(len(output_cntxt)>0):
        last_line=max(output_cntxt)
        if((last_line+1)<(idx) and (out_str!='')):
            out_str='==================================================================='+"\n"+out_str
    
    return out_str


def file_diff(start_file,end_file,show_nops=False,show_ln_diff=True,cntxt_lns=3,verbose=True,use_color=False):
    start_fp=open(start_file,'r')
    start_fc=start_fp.read()
    start_fp.close()
    
    end_fp=open(end_file,'r')
    end_fc=end_fp.read()
    end_fp.close()
    
    #TODO: diff in "chunks" to be more resource-efficient
    
    op_queue,op_cnt=diff_ops(start_fc.split("\n"),end_fc.split("\n"),debug=False)
    start_trans,diff_trans,end_trans=visual_diff(op_queue,by_line=True,use_color=use_color)
    
    import math
    #the number of digits is the ceiling of the log base 10 of the file length
    digits=int(math.ceil(math.log(len(diff_trans))/math.log(10)))
    
    output_cntxt=[]
    
    for i in range(0,len(diff_trans)):
        if(not show_nops and diff_trans[i]!=''):
            for j in range(i-cntxt_lns,i):
                if(j>=0 and (not j in output_cntxt)):
                    print(visual_line_diff(start_trans[j],diff_trans[j],end_trans[j],digits,j,True,show_ln_diff,output_cntxt,use_color=use_color))
                    output_cntxt.append(j)
        
        out_str=visual_line_diff(start_trans[i],diff_trans[i],end_trans[i],digits,i,show_nops,show_ln_diff,output_cntxt,use_color=use_color)
        if(out_str!='' and (not i in output_cntxt)):
            print(out_str)
            output_cntxt.append(i)
        
        if(not show_nops and diff_trans[i]!=''):
            for j in range(i+1,i+1+cntxt_lns):
                if(j<len(diff_trans) and (not j in output_cntxt)):
                    print(visual_line_diff(start_trans[j],diff_trans[j],end_trans[j],digits,j,True,show_ln_diff,output_cntxt,use_color=use_color))
                    output_cntxt.append(j)
    
    if(verbose):
        #this is just a summary for human uses
        #if piping this output to another program, you can use
        # | head -n-2
        #to remove this output
        print('')
        print('Info: '+str(op_cnt)+' lines changed (of '+str(len(diff_trans))+' considered lines)')
    

def diff_desc(op_queue):
    desc_str=''
    #for each operation
    for op in op_queue:
        if(op[0]=='nop'):
            desc_str+='n'
        elif(op[0]=='sub'):
            desc_str+='s'+op[2]
        elif(op[0]=='del'):
            desc_str+='d'
        elif(op[0]=='ins'):
            desc_str+='i'+op[1]
    
    return desc_str

def diff_patch(start_str,diff_desc_str):
    ret_str=''
    
    start_idx=0
    desc_idx=0
    while(desc_idx<len(diff_desc_str)):
        
        if(diff_desc_str[desc_idx]=='n'):
            ret_str+=start_str[start_idx]
            start_idx+=1
            desc_idx+=1
        elif(diff_desc_str[desc_idx]=='d'):
            start_idx+=1
            desc_idx+=1
        elif(diff_desc_str[desc_idx]=='s'):
            ret_str+=diff_desc_str[desc_idx+1]
            desc_idx+=2
            start_idx+=1
        elif(diff_desc_str[desc_idx]=='i'):
            ret_str+=diff_desc_str[desc_idx+1]
            desc_idx+=2
    
    return ret_str

import os
def get_dictionary(dict_paths=[os.getenv('HOME')+'/words.txt',os.getenv('HOME')+'/documents/dictionaries-wordlists/words.txt','/usr/dict/words','/usr/share/dict/words'],hard_fail=True):
    
    path=''
    for dict_path in dict_paths:
        if(os.path.exists(dict_path)):
            path=dict_path
            break
    else:
        print('Error: Could not find a dictionary in the default locations')
        if(hard_fail):
            exit(1)
        return []
    
    fp=open(path,'r')
    words=fp.read().split("\n")
    fp.close()
    
    return words

def similarity_perc(op_cnt,start_line,end_line):
    return (round((1.0-((op_cnt*1.0)/max(len(start_line),len(end_line))))*100.0,2)) if max(len(start_line),len(end_line))>0 else 100

#check a given word against the dictionary
def spellcheck(word,dictionary,edit_dist=1,debug=True,use_color=False):
    match=False
    close_words=[]
    for dict_word in dictionary:
        if(word==dict_word):
#            print('Found word \''+word+'\' in dictionary')
            print('CORRECT spelling for \''+word+'\'')
            match=True
            break
    if(not match):
        transpositions=[]
        for i in range(1,len(word)):
            transpositions.append(word[0:i-1]+word[i]+word[i-1]+word[i+1:])
#        if(debug):
#            print('transpositions: '+str(transpositions))
        
        transpose_matches=[]
        
        print('')
        print('Did not find exact match in dictionary for word \''+word+'\'; checking close matches...')
        for dict_word in dictionary:
            #words which cannot be close (just based on length difference)
            #are skipped for efficiency
            if(abs(len(dict_word)-len(word))>edit_dist):
                continue
            
            #if this is a transposition of the given word then it is by definition close
            transposition_match=False
            for transposition in transpositions:
                if(dict_word==transposition):
                    transposition_match=True
                    transpose_matches.append(dict_word)
            
            ops,op_cnt=diff_ops(word,dict_word,debug=False)
            if((op_cnt<=edit_dist) or transposition_match):
                if(not transposition_match):
                    close_words.append(dict_word)
                
                if(not debug):
                    continue
                
                print('Did you mean \''+dict_word+'\'? (word was \''+word+'\'; edit distance '+str(op_cnt)+'; similarity '+
                    str(similarity_perc(op_cnt,word,dict_word))
                    +' percent)')
                start_trans,diff_str,end_trans=visual_diff(ops,use_color=use_color)
                print(start_trans)
                print(diff_str)
                print(end_trans)
                print('')
        
        #sort by similarity
        close_words.reverse()
        close_words.sort(key=lambda dict_word: (1.0-((diff_ops(word,dict_word,debug=False)[1]*1.0)/max(len(word),len(dict_word)))))
        close_words.reverse()
        
        #include transposition matches
        #and matches within the requested edit distance
        close_words=transpose_matches+close_words
        
        print('INCORRECT spelling for \''+word+'\'')
    return (match,close_words)

if(__name__=='__main__'):
    import sys
    
    #handle --color first
    #this is optional and shifts other arguments if it's given
    if((len(sys.argv)>1) and (sys.argv[1]=='--color')):
        use_color=True
        sys.argv=[sys.argv[0]]+sys.argv[2:]
    
    quiet_mode=False
    #handle --quiet
    #this is similar to --color in parsing
    #but note that --color must come BEFORE --quiet when both are used
    if((len(sys.argv)>1) and (sys.argv[1]=='--quiet')):
        quiet_mode=True
        sys.argv=[sys.argv[0]]+sys.argv[2:]
    
    if(len(sys.argv)<4):
        print('Usage: '+sys.argv[0]+' [--color] [--quiet] ( [--line <start line> <end line> [spellcheck edit distance]] | [--file <start file> <end file> [--nolndiff]] | [--mkpatch <start line> <end line>] | [--appatch <start line> <patch string>] )')
        exit(1)
    
    #show the differences between 2 files (line by line)
    if(sys.argv[1]=='--file'):
        show_ln_diff=True
        if(len(sys.argv)>4):
            show_ln_diff=False if (sys.argv[4]=='--nolndiff') else True
        file_diff(sys.argv[2],sys.argv[3],show_ln_diff=show_ln_diff,use_color=use_color)
    #show the difference between 2 strings (lines) and optionally spellcheck
    elif(sys.argv[1]=='--line'):
        start_line=sys.argv[2]
        end_line=sys.argv[3]
        
        edit_dist=quick_diff(start_line,end_line,debug=(not quiet_mode))[0]
        print(str(edit_dist)+' is the edit distance ('+str(similarity_perc(edit_dist,start_line,end_line))+' percent similarity)'+"\n")
        
        ops=diff_ops(start_line,end_line,debug=False)[0]
    #    print(str(ops)+"\n")
        
        start_trans,diff_str,end_trans=visual_diff(ops,use_color=use_color)
        print(start_trans)
        print(diff_str)
        print(end_trans)
        
        if(not quiet_mode):
            print('')
            desc_str=diff_desc(ops)
            print('desc_str:         '+desc_str)
        #    print('original:         '+start_line)
            patched_str=diff_patch(start_line,desc_str)
            print('patched original: '+patched_str)
            assert(patched_str==end_line)
        
        edit_dist=1
        if(len(sys.argv)>4):
            edit_dist=int(sys.argv[4])
        
        print('')
        print('Spellcheck? (y/n)')
        option=input()
    #    option='n'
        print('got option '+option)
        print('')
        if(option.lower().startswith('y')):
            dictionary=get_dictionary()
            for word in [start_line,end_line]:
                if(word.find(' ')==-1):
                    match,close_words=spellcheck(word,dictionary,edit_dist=edit_dist,use_color=use_color)
                    print('close_words='+str(close_words))
                else:
                    print('Skipping \"'+word+'\" because it\'s not a word (it contains spaces)')
    #make a character-by-character "patch" that transforms the given start line into the given end line
    elif(sys.argv[1]=='--mkpatch'):
        start_line=sys.argv[2]
        end_line=sys.argv[3]
        patch_str=diff_desc(diff_ops(start_line,end_line,debug=False)[0])
        print(patch_str)
    #apply a character-by-character "patch" (from --mkpatch) to the given start line
    #this should result in the given end line which was used with the --mkpatch call
    elif(sys.argv[1]=='--appatch'):
        start_line=sys.argv[2]
        patch_str=sys.argv[3]
        print(diff_patch(start_line,patch_str))
    else:
        print('Unsupported diff type '+sys.argv[1]+'; please use --file, --line, --mkpatch, or --appatch')
    

