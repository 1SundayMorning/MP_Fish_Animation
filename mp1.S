
.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16
        ON      = 1
        OFF     = 0
        RANGE   = 1999
        COPY_POP = 12
        FAIL     = -1


# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX 
mp1_poke:
        
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret

mp1_rtc_tasklet:
        #Tasklet updates state of image. Walks down entire list, checks
        #that countdown is zero. If it is, we change the character depending
        #on the elem's status. 
        #Register Table:
        #EAX: address of elem to write
        #EBX: General purpose
        #ECX: character to write to elem
        #EDX: holds head pointer
        #
        #
        #inputs: none
        #outputs: non
        #
        pushl %EBP                    #set up stack frame
        movl %ESP, %EBP
        pushl %EBX

        andl $0, %EDX                   #clear EDX
        movl mp1_list_head, %EDX        #EDX now holds head pointer

TASKLET_LOOP:
        andl $0, %EBX                           #clear EBX
        movw COUNTDOWN(%EDX), %BX
        subw $1, %BX                            #counter decrement
        movw %BX, COUNTDOWN(%EDX)     
        #movw COUNTDOWN(%EDX), %BX
       
        cmpl $0, %EBX                           #check if countdown is zero
        jne OUT_STAT_SUB
       
        andl $0, %EBX
        movw STATUS(%EDX), %BX                  #EBX has status
        cmpl $ON, %EBX
        je STAT_ONE

        andl $0, %EAX
        andl $0, %ECX
        movb ON_CHAR(%EDX), %CL                 #arg for poke. char to write
        movw LOCATION(%EDX), %AX
        addl %EAX, %EAX
        pushl %EDX
        call mp1_poke
        popl %EDX
        movw $ON, STATUS(%EDX)                   #change status to 1

        andl $0, %EBX
        movw ON_LENGTH(%EDX), %BX
        movw %BX, COUNTDOWN(%EDX)
        jmp OUT_STAT_SUB

STAT_ONE:
        andl $0, %EAX
        andl $0, %ECX
        movb OFF_CHAR(%EDX), %CL         #arg for poke. char to write
        movw LOCATION(%EDX), %AX
        addl %EAX, %EAX
        pushl %EDX
        call mp1_poke
        popl %EDX
        movw $OFF, STATUS(%EDX)               #change status to 0
        andl $0, %EBX
        movw OFF_LENGTH(%EDX), %BX
        movw %BX, COUNTDOWN(%EDX)

OUT_STAT_SUB:
        andl $0, %EBX
        movl NEXT(%EDX), %EBX
        movl %EBX, %EDX
        cmpl $0, %EBX
        je DONE
        jmp TASKLET_LOOP

        

DONE:
        popl %EBX
        LEAVE
	ret

mp1_ioctl:
        #IOCTL serves as a jumptable implementation
        #inputs are command number, gives which function to execute
        #output -1 if fail
        #no output otherwise
        #
        #EDX holds command
        #
        #
        movl    8(%ESP), %EDX   #edx gets command, located on stack, 2 entries down

        cmpl    $3, %EDX        #compare edx - 3 to check for valid command
        jg      ERROR
        jmp     *table(,%EDX,4)        #jumptable[edx*4]
        
ERROR:
        movl    $FAIL, %EAX       #eax <- -1 (hopefully)
	ret

table:
        .long mp1_ioctl_add, mp1_ioctl_remove, mp1_ioctl_find, mp1_ioctl_sync

mp1_ioctl_add:
        #allocates memory for the new elem. copies blink struct to new elem.
        #updates head pointer. then turns elem "on"
        #
        #
        #
        #inputs: pointer to blink structure
        #outputs zero if success. -1 if fail.
        #Registers Used:
        #EAX: returns of functions
        #EBX: holds location of malloced memory, first location of struct instantiation
        #ECX: general
        #EDX: general
        #ESP: top of stack
        #EBP: bottom of stack
        #
        #

        pushl %EBP                    #set up stack frame
        movl %ESP, %EBP
        pushl %EBX                    #callee saved Register

        pushl %ECX                   
        pushl %EDX
        pushl $STRUCT_SIZE            #Tell malloc to allocate 16 bytes or some shit
        call mp1_malloc               #call malloc
        popl %EDX
        popl %ECX
        addl $4, %ESP                 #stack pop with no destination. Throw away data.

        movl %EAX, %EBX               #location of allocated memory saved in EBX

        cmpl $0, %EAX                 #test that malloc was successful
        je MALLOC_FAIL


        movl 8(%EBP), %ECX            #get head of blink struct
        cmpl $0, %ECX
        je ADD_ERROR
 

        pushl $STRUCT_SIZE            #size aka 'n' 
        pushl %ECX                    #should be pushing list head pointer
        pushl %EBX                    #to? assuming first addr of malloc'd mem.
        call mp1_copy_from_user       #call function to copy struct to mem
        addl $COPY_POP, %ESP                #pop args off stack

        cmpl $0, %EAX                 #test that mp1_copy_from_user returned 0
        jne ADD_ERROR
        
        andl $0, %ECX                 #clear ECX

        movw ON_LENGTH(%EBX), %CX     #ECX should now have on_length
        movw %CX, COUNTDOWN(%EBX)     #attempt to set countdown to on_length

        andl $0, %ECX                 #clear ECX again
        movl $1, %ECX                 #puts 1 into ECX

        movw %CX, STATUS(%EBX)        #attempt to set status to 1


        movb ON_CHAR(%EBX), %CL       #first arg for poke
        andl $0, %EAX                 #clear eax
        movw LOCATION(%EBX), %AX      #second arg for poke
        cmpl $RANGE, %EAX
        ja ADD_ERROR
        addl %EAX, %EAX
        pushl %EDX
        call mp1_poke
        popl %EDX

        andl $0, %EDX
        movl mp1_list_head, %EDX      #edx holds list head pointer
        movl %EBX, mp1_list_head
        movl %EDX, NEXT(%EBX)

        andl $0, %EAX           #clears eax

        jmp stack_frame_teardown


ADD_ERROR:
        pushl %EBX
        call mp1_free
        addl $4, %ESP
        movl $FAIL, %EAX
        jmp stack_frame_teardown

MALLOC_FAIL:
        movl $FAIL, %EAX
        jmp stack_frame_teardown

stack_frame_teardown:
        popl %EBX
        LEAVE
        ret

shaymus_search:
        #Searches linked list for elem with matching location as input. Finds by
        #walking down linked list. At the same time, a second register store pointer
        #to previous elem. This functionality is used in remove. If the head is returned,
        #both output registers will hold the same value
        #
        #inputs: location. passed in CX
        #outputs: EAX gets elem with matching location. EBX gets prev elem.
        #
        #%EBX gets prev elem, also clobbered
        #EAX gets actual elem
        #location in #CL
        #clobbers %EDX

        andl $0, %EAX
        andl $0, %EBX
        andl $0, %EDX
        movl mp1_list_head, %EBX        #load head into EBX
        cmpl $0, %EBX                   #check head isn't null
        je SEARCH_ERROR
        movw LOCATION(%EBX), %DX        #check that head is what we're looking for
        cmpw %CX, %DX
        je FOUND_HEAD
TOP:        
        andl $0, %EDX                   #EDX cleared
        movl NEXT(%EBX), %EAX           #EAX gets next
        cmpl $0, %EAX                   #check that next isn't NULL
        je SEARCH_ERROR                 #if next is NULL don't dereference
        movw LOCATION(%EAX), %DX        #EDX has location of check link
        cmpw %CX, %DX
        je FOUND
        movl %EAX, %EBX                 #Move down list, top gets next
        jmp TOP
        
FOUND_HEAD:
        movl %EBX, %EAX   
FOUND:
        ret
SEARCH_ERROR:
        movl $FAIL, %EAX
        ret



mp1_ioctl_remove:
        #takes location, searches for elem in location, then removes elem with
        #matching location value
        #
        #inputs: location
        #outputs: zero on success, -1 on fail.
        #
        #EAX: elem to remove
        #EBX: elem above.
        #CX: Location
        #DX: elem location
        #

        pushl %EBP                    #set up stack frame
        movl %ESP, %EBP
        pushl %EBX
        
        andl $0, %EAX
        andl $0, %EBX
        andl $0, %ECX
        andl $0, %EDX
        
        movw 8(%EBP), %CX              #CX holds location param
        cmpw $RANGE, %CX
        ja REMOVE_FAIL
        pushl %EDX
        call shaymus_search             #search for mem with same location
        popl %EDX

        andl $0, %EDX
        movl mp1_list_head, %EDX
        cmpl %EAX, %EDX
        je REMOVE_HEAD
        cmpl $FAIL, %EAX
        je REMOVE_FAIL

        movl NEXT(%EAX), %EDX           #save the next addr of what we'll delete
        movl %EDX, NEXT(%EBX)           #next of above elem skips next elem
        jmp REMOVE_FREE

REMOVE_HEAD:
        movl NEXT(%EAX), %EDX
        movl %EDX, %EBX
        movl %EBX, mp1_list_head
REMOVE_FREE:
        pushl %EAX                      #push elem to delete 
        call mp1_free                   #delete elem
        addl $4, %ESP                   #update stack
        jmp REMOVE_SUCCESS
        
REMOVE_FAIL:
        movl $FAIL, %EAX
        jmp EXIT_REMOVE

REMOVE_SUCCESS:
        movl $0, %EAX
        jmp EXIT_REMOVE

EXIT_REMOVE:
        popl %ESI
        popl %EBX
        LEAVE
	ret
        
mp1_ioctl_find:
        #
        #
        #
        #takes a pointer to a blink struct. Location parameter is extraced from struct.
        #The linked list is then searched for elem with same location. The blink struct is
        #then copied to userspace
        #
        #
        #input: pointer to blink struct
        #output: 0 on success, -1 on failure
        #
        #EDX: holds passed blink struct
        #CX: location
        #EAX: outputs
        #
        #
        pushl %EBP                    #set up stack frame
        movl %ESP, %EBP
        pushl %EBX                    #callee saved Register
        pushl %ESI

        movl 8(%EBP), %EDX              #EDX takes arg
        cmpl $0, %EDX                   #check valid
        je FIND_ERROR

        andl $0, %ECX                   #clear edx to hold location
        movw LOCATION(%EDX), %CX        #location extracted, put in CX

        cmpw $RANGE, %CX
        ja FIND_ERROR

        pushl %EDX
        pushl %EBX
        call shaymus_search             #If found, ptr in EAX
        popl %EBX
        popl %EDX

        cmpl $0, %EAX
        jb FIND_ERROR                   #EAX will hold -1 if search unsuccessful

        pushl $STRUCT_SIZE
        pushl %EAX
        pushl %EDX
        call mp1_copy_to_user
        addl $COPY_POP, %ESP                   #pop stack

        andl $0, %EAX
        jmp find_out

FIND_ERROR:
        andl $0, %EAX
        addl $FAIL, %EAX
        jmp find_out

find_out:
        popl %ESI
        popl %EBX
        LEAVE
	ret

mp1_ioctl_sync:
        #Takes locations of two structs. Copies timing info from link 1 to 2, which syncs the
        #elems. 
        #
        #inputs: two locations 
        #outputs: 0 on success, -1 on failure
        #
        #
        #EBX has location 1
        #ESI has location 2
        #EAX has output
        #
        pushl %EBP                         #set up stack frame
        movl %ESP, %EBP
        pushl %EBX                         #callee saved Register
        pushl %ESI

        andl $0, %EBX
        andl $0, %ESI
        movw 8(%EBP), %BX                   #location 2
        movw 10(%EBP), %SI                  #location 1

        andl $0, %ECX
        movw %BX, %CX
        pushl %EDX
        pushl %EBX
        call shaymus_search
        popl %EBX
        popl %EDX

        cmpl $0, %EAX
        jb SYNC_ERROR

        movl %EAX, %EBX                    #EBX now has addr of elem 1

        andl $0, %ECX
        movw %SI, %CX
        pushl %EDX
        pushl %EBX
        call shaymus_search
        popl %EBX
        popl %EDX

        cmpl $0, %EAX
        jb SYNC_ERROR

        movl %EAX, %ESI                    #ESI now has addr of elem 2

        andl $0, %EDX
        movw ON_LENGTH(%ESI), %DX       #char 2 on_length
        movw %DX, ON_LENGTH(%EBX)       #char 
        movw OFF_LENGTH(%ESI), %DX
        movw %DX, OFF_LENGTH(%EBX)
        movw COUNTDOWN(%ESI), %DX
        movw %DX, COUNTDOWN(%EBX)
        movw STATUS(%ESI), %DX
        movw %DX, STATUS(%EBX)

        andl $0, %EAX
        andl $0, %ECX
        movw LOCATION(%EBX), %AX
        addl %EAX, %EAX
        cmpl $OFF, STATUS(%EBX)                 #check that status is off
        je OFF_SYNC

        movw OFF_CHAR(%EBX), %CX
        jmp SYNC_POKE
OFF_SYNC:
        movw ON_CHAR(%EBX), %CX
SYNC_POKE:
        pushl %EDX
        call mp1_poke
        popl %EDX

        andl $0, %EAX
        jmp sync_out

SYNC_ERROR:
        andl $0, %EAX
        addl $FAIL, %EAX
        jmp sync_out

sync_out:
        
        popl %ESI
        popl %EBX
        LEAVE
	ret


.end
