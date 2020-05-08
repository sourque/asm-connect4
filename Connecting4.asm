; Final project for Andrew's Assembly Class :) CSC-314
; 08 May 2020

; =================
; === CONSTANTS ===
; =================

%define HEIGHT		7
%define WIDTH		36
%define STARTX		0
%define STARTY		0
%define MAXX		24
%define SPACECHAR	32
%define EXITCHAR	'x'
%define LEFTCHAR	'a'
%define RIGHTCHAR	'd'

; Portions of socket code shamelessly ripped from 
; https://gist.github.com/bobbo/e1e980262f2ddc8db3b8
struc sockaddr_in
	.sin_family		resw 1
	.sin_port		resw 1
	.sin_addr		resd 1
	.sin_zero		resb 8
endstruc

segment .data

	; ===================
	; === SOCKET DATA ===
	; ===================

	; Create socket struct
	sock_struct istruc sockaddr_in
		at sockaddr_in.sin_family, 	dw 2			; AF_INET
		at sockaddr_in.sin_port, 	dw 0xfecf		; i have tried so much crap with this port
		at sockaddr_in.sin_addr, 	dd 0			; INADDR_ANY. It would be INADDR_LOOPBACK,
													; 	but that causes a segfault (???).
		at sockaddr_in.sin_zero, 	dd 0, 0
	iend

	sockaddr_in_len     equ $ - sock_struct			; Length of struct

	sock_err_msg        db "Failed to initialise socket!", 10, 0
	sock_err_msg_len    equ $ - sock_err_msg 		; This is very convenient

	bind_err_msg        db "Failed to bind socket to listening address!", 10, 0
	bind_err_msg_len    equ $ - bind_err_msg

	lstn_err_msg        db "Failed to listen on socket!", 10, 0
	lstn_err_msg_len    equ $ - lstn_err_msg

	accept_err_msg      db "Could not accept connection attempt!", 10, 0
	accept_err_msg_len  equ $ - accept_err_msg

	conn_err_msg        db 13, 10, "Connection closed!", 10, 0
	conn_err_msg_len    equ $ - conn_err_msg


	board_init 			dd	'🦊🦊🦊🦊🦊🦊🦊',14,10, \
							'🔵🔵🔵🔵🔵🔵🔵',14,10, \
							'🔵🔵🔵🔵🔵🔵🔵',14,10, \
							'🔵🔵🔵🔵🔵🔵🔵',14,10, \
							'🔵🔵🔵🔵🔵🔵🔵',14,10, \
							'🔵🔵🔵🔵🔵🔵🔵',14,10, \
							'🔵🔵🔵🔵🔵🔵🔵',14,10

	player1	   			dd	'😂',0
	player2	   			dd	'🔴',0

	; terminal mode and other system commands
	mode_r				db "r",0
	raw_on_cmd			db "stty raw -echo",0
	raw_off_cmd			db "stty -raw echo",0
	clear_screen_cmd	db "clear",0

	; things the program will print
	status_str			db "Connecting4 v1.0 || Move #%d", 13, 10, 0
	help_str			db 	13, 10, "Move left (a) and right (d).", \
							13, 10, "Press Space to place.", 13, 10, 10, 0
    usage_str			db	"Usage:  connecting4 i{nvite} [user] OR", 10, 9, \
									"connecting4 j{oin} [port]", 10, 0
    waiting_str			db 	13, 10, "Waiting for opponent...", 10, 0
    invite_str			db 	"echo ", 34, "Hey gamer! You've been invited to ", \
							"play Connecting4. Type:", 10, 9, "connecting4 join", \
							10, "to accept.", 34, " | write %s", 10, 0

segment .bss

	; networking dynamic reserved data
	sock			resw 	2	; service socket fd
	client			resw 	2	; client socket fd
	player_move 	resd 	1	; X-value of player move
	move_count 		resd 	1	; move counter
	literal_trash	resb 	1 	; holds garbage data
	read_count 		resw 	2   ; how much data was read in

	; this array stores the current rendered gameboard (HxW)
	board			resd	(HEIGHT * WIDTH)
	board_data		resb    (6 * 7)

	; these variables store the current player position
	xpos			resd	1
	ypos			resd	1

	; stores command to invite player via write
	invite_cmd 		resb	100
	
	; stores name of challenged user or port, and actual port
	userport 		resb	100
	port			resw	1

	; stores player number
	player			resb	1
	
	; switch to compensate for bad programming
	switch			resd	1

segment .text

	global	asm_main	; internal functions
	global  raw_on
	global  raw_off
	global  init_board
	global  render

	extern	system 		; system and I/O functions
	extern	putchar
	extern	getchar
	extern	printf
	extern	sprintf
	extern	fopen
	extern	fread
	extern	fgetc
	extern	fclose
	extern 	sleep
	extern	exit
	
	extern	socket		; networking calls (net/socket.c)
	extern	bind
	extern	listen
	extern 	accept
	extern 	connect
	extern 	getsockname

asm_main:

	;*************** START OF MAIN ***************
	mov 	esi, [ebp + 12]			
	mov 	eax, [esi + 4]			; *argv[1]
	test 	eax, eax				; If null, print bad usage
	je		bad_usage
	mov		edi, eax 				; EDI stores command (invite or connect)
	mov 	eax, [esi + 8] 			; *argv[2]
	mov		DWORD [userport], eax
	jmp 	sop 					; Start!

	bad_usage:
	; ebp-4, ebp-8
		push 	usage_str
		call 	printf
		add 	esp, 8
		call 	exit
		ret
	
	sop:
	enter 	0,0 					; Actually set up the stack frame lol
	pusha

	mov		DWORD [switch], 1
	mov		eax, [edi]
	cmp 	al, 'i'
	je 		inviter
	cmp 	al, 'j'
	je 		invitee 	
	push 	usage_str				; Print bad usage (but without exit)
	call 	printf
	add 	esp, 4
	jmp 	eop

	inviter:
		call	establish_listener

		mov		BYTE [player], 1
		push	waiting_str
		call	printf
		add		esp, 4

		push	DWORD [userport]
		push 	invite_str
		push	invite_cmd
		call	sprintf
		add 	esp, (4 * 4)

		push	invite_cmd
		call	system
		add		esp, 4

		call	wait_for_conn
		jmp 	sog

	invitee:
		mov		BYTE [player], 2
		call 	connect_socket

	sog:

	; Render board and start game
	mov		DWORD [move_count], 0
	call	raw_on 				 ; Put terminal in raw mode
	call	init_board 			 ; Initialize board

	mov		DWORD [xpos], STARTX ; Start player position 
	mov		DWORD [ypos], STARTY ; Start player position 

	game_cycle:

		; draw the game board
		call	render

		; get an action from the user
		mov		bl, BYTE [player]
		cmp		bl, 1
		je	 	wait_p1
		jmp	 	wait_p2

		wait_p1:
		cmp		DWORD [switch], 1		; If switch == 1 for P1, wait
		je		wait_remote_input
		call	getchar
		jmp		end_wait

		wait_p2:
		mov		ecx, DWORD [switch]
		cmp		DWORD [switch], 1		; If switch == 0 for P2, wait
		jne		wait_remote_input
		call	getchar
		jmp 	end_wait

		wait_remote_input:
			push	waiting_str
			call	printf
			add		esp, 4
			call	get_remote_input
			push	DWORD [player_move]
			call	place_piece
			add		esp, 4
			not		DWORD [switch]

		end_wait:

		; determine action
		cmp		eax, EXITCHAR
		je		game_end
		cmp		eax, LEFTCHAR
		je		move_left
		cmp		eax, RIGHTCHAR
		je		move_right
		cmp		eax, SPACECHAR
		je		piece_add
		jmp		input_end

		move_left:
			cmp		DWORD [xpos], STARTX
			jle		input_end
			sub		DWORD [xpos], 4
			jmp		input_end
		move_right:
			cmp		DWORD [xpos], MAXX
			jge		input_end
			add		DWORD [xpos], 4
			jmp		input_end
		piece_add:
			push	DWORD [xpos]
			mov		eax, DWORD [xpos]
			call 	place_piece
			add		esp, 4
			not		DWORD [switch]
		input_end:

	jmp		game_cycle

	game_end:
	call raw_off		; raw moden't

	eop:

	;*************** END OF MAIN ***************
	popa
	xor		eax, eax
	leave
	ret

; ============================
; === GAME LOGIC FUNCTIONS ===
; ============================

check_win:
	; I was going to have a function to check if someone has won
	; but I think that's part of the fun
	; where you could end up missing where you won
	ret

place_piece:
	cdq
	mov		eax, DWORD [esp + 4]
	mov		edi, eax
	mov		ebx, 4
	div		ebx
	mov		ebx, eax 		; Divide the X value by 4 (since it hops by 4s)
	mov		eax, 0
	topl:
		mov		al, BYTE [board_data + ebx]	; Check if spot is empty
		cmp 	al, 0						; If spot is not empty, jump to end and -7
		jne		eopl
		cmp		ebx, 42						; If on last row, skip check
		jge		eopl
		add		ebx, 7						; Increment row
		jmp 	topl

	eopl:

	cmp		ebx, 6
	jle		game_cycle	; If top row (full), invalid move, jump to start
						; why does this work?

	sub		ebx, 7
	mov		al, BYTE [player]
	mov		BYTE [board_data + ebx], al

	cdq						; Write emoji to board
	add		ebx, 7			; Add 7 to compensate for the top emoji row
	mov		eax, ebx
	mov		ecx, 7
	div		ecx				; Find how many rows down
	mov		ecx, edx		; Remainder is offset. Save in ecx
	mov		edx, 36 		; Result is rows down. Multiply by 36
	mul		edx				; EAX now contains row offset
	mov		ebx, eax		; Save row value
	mov		eax, ecx		; Multiply remainder by 4
	mov		edx, 4
	mul		edx				; EAX contains adjusted x offset
	add		eax, ebx		; EAX now contains correct index

		mov		bl, BYTE [player]
		cmp		bl, 1
		je		boardp_player1
		jmp		boardp_player2

		boardp_player1:
		mov		ecx, DWORD [switch]
		cmp		ecx, 1
		je		board_p2
		jmp		board_p1

		boardp_player2:
		mov		ecx, DWORD [switch]
		cmp		ecx, 1
		je		board_p2
		jmp		board_p1

		board_p1:
		mov		BYTE [board + eax], 0xf0		; This is so jank
		mov		BYTE [board + eax + 1], 0x9f	; These are the bytes for :joy:
		mov		BYTE [board + eax + 2], 0x98
		mov		BYTE [board + eax + 3], 0x82
		jmp		end_boardp

		board_p2:
		mov		BYTE [board + eax], 0xf0		; hell yeah
		mov		BYTE [board + eax + 1], 0x9f
		mov		BYTE [board + eax + 2], 0x94
		mov		BYTE [board + eax + 3], 0xb4

		end_boardp:

	mov		DWORD [player_move], edi 			; Send that badboy on over
	call	_write
	inc		DWORD [move_count]
	end_of_place:
	ret


; ============================
; === GAME BOARD FUNCTIONS ===
; ============================

init_board:
	cld
	mov		ecx, 42 		; Clear game data board
	mov		edi, board_data
	mov		al, 0
	rep		stosb
	
	cld
	mov		esi, board_init	; Copy initial board into live board buffer
	mov		edi, board
	mov		ecx, 90
	rep		movsd

	ret

render:
	enter	0,0

	; two ints, for two loop counters
	sub		esp, 8

	; clear the screen
	push	clear_screen_cmd
	call	system
	add		esp, 4

	; print status and help
	mov		eax, DWORD [move_count]
	push 	eax
	push	status_str
	call	printf
	add		esp, (4 * 2)

	push	help_str
	call	printf
	add		esp, 4


	; Loop rows
	mov		DWORD [ebp-4], 0
	y_loop_start:
	cmp		DWORD [ebp-4], HEIGHT
	je		y_loop_end

		; Loop columns
		mov		DWORD [ebp-8], 0
		x_loop_start:
		cmp		DWORD [ebp-8], WIDTH
		je 		x_loop_end

			mov		eax, [xpos]
			cmp		eax, DWORD [ebp-8]
			jne		print_board				; Player's x-pos did not match
			mov		eax, [ypos]
			cmp		eax, DWORD [ebp-4]
			jne		print_board				; Players y-pos did not match
				mov		al, BYTE [player]	; Both matched, print correct player
				cmp		al, 1
				jne 	print_player2

				push player1
				jmp end_playerchoice

				print_player2:
				push player2

				end_playerchoice:

				call	printf
				add 	esp, 4
				jmp		print_end
			print_board:
				mov		eax, [ebp-4]
				mov		ebx, WIDTH
				mul		ebx
				add		eax, [ebp-8]
				mov		ebx, DWORD [board + eax]
				push	ebx
				call	putchar				; Not player, just print board dword
				add		esp, 4
			print_end:

		inc		DWORD [ebp-8]
		jmp		x_loop_start
		x_loop_end:

		push	13			; Write carriage return (for raw mode)
		call 	putchar
		add		esp, 4

	inc		DWORD [ebp-4]
	jmp		y_loop_start
	y_loop_end:

	mov		esp, ebp
	pop		ebp
	ret


; =========================
; === NETWORKING FUNCS ===
; =========================

establish_listener:
	mov		DWORD [sock], 0		; Clear socket and client values
	mov		DWORD [client], 0
	call     _socket			; Should probably set sockopts here...
	call     _listen
	ret

wait_for_conn:
	call     _accept
	ret

get_remote_input:
	call     _read

	mov		eax, [read_count]	; Check if client died
	cmp		eax, 0
	je		read_complete
	ret

	read_complete:				; Close socket
	mov		eax, [client]
	call	_close_sock
	mov		DWORD [client], 0
	call	raw_off
	call	_connect_fail
	ret

connect_socket:
	mov		DWORD [sock], 0
	mov		DWORD [client], 0
	call	_socket
	call	_connect
	call	_write			; Writing 4 trash bytes... so then we 
							; can throw away from the start. Hard to explain
	ret

get_port_number:
	push	sockaddr_in_len
	push	sock_struct
	push	DWORD [sock]
	call 	getsockname
	add		esp, (4 * 3)

	cmp		eax, 0
	jl		_socket_fail

	mov		edx, 0
	mov		dx, WORD [sock_struct + 4]
	mov		DWORD [port], edx
	ret

; =========================
; === UTILITY FUNCTIONS ===
; =========================

raw_on:
	push	raw_on_cmd
	call	system
	add		esp, 4
	ret

raw_off:
	push	raw_off_cmd
	call	system
	add		esp, 4
	ret
 

; ========================
; === SOCKET FUNCTIONS ===
; ========================

_socket:
	push	0
	push	1				; SOCK_STREAM
	push	2				; AF_INET
	call	socket
	add		esp, (3 * 4)

	cmp		eax, 0			; Ensure no error from socket() call
	jle		_socket_fail

	mov		[sock], eax		; It worked -- store fd in sock

	ret

_listen:
	push	sockaddr_in_len		; Bind to socket
	push	sock_struct
	push	DWORD [sock]
	call	bind
	add		esp, (3 * 4)

	cmp		eax, 0				; Check that bind succeeded
	jl		_bind_fail

	push	128					; Did succeed, now call listen
	push	DWORD [sock]
	call	listen
	add		esp, (2 * 4)

	cmp		eax, 0				; Ensure listen worked
	jl		_listen_fail
	ret

_accept:
	push	0					; As if I cared about the client
	push	0
	push	DWORD [sock]
	call	accept
	add		esp, (3 * 4)

	cmp		eax, 0				; Ensure accept succeeded
	jl		_accept_fail
	mov     [client], eax		; It did-- store fd in client

	ret

_connect:
	push	sockaddr_in_len 	; socket address length
	push	sock_struct			; socket structure
	push	DWORD [sock]		; socket fd
	call	connect
	add		esp, (3 * 4)

	cmp		eax, 0				; Ensure connected successfully
	jl		_connect_fail

	mov		eax, DWORD [sock]	; Copy sock to client for P2
	mov		DWORD [client], eax
	ret

; ================================
; === READ/WRITE NET FUNCTIONS ===
; ================================

_read:
	mov     eax, 3        		; SYS_READ
	mov     ebx, [client]   	; client socket fd
	mov     ecx, literal_trash
	mov     edx, 4				; clearing a DWORD
	int		0x80 

	mov     eax, 3        		; SYS_READ
	mov     ebx, [client]   	; client socket fd
	mov     ecx, player_move    ; player move buffer
	mov     edx, 4       		; reading a DWORD
	int		0x80 

	mov     [read_count], eax	; should be 4 except when socket dies
	ret 

_write:
	mov     eax, 4				; SYS_WRITE
	mov     ebx, [client]		; client socket fd
	mov     ecx, player_move     
	mov     edx, 4 				; sending one DWORD
	int		0x80
	ret

_close_sock:
	mov		ebx, eax		; socket fd passed through EAX
	mov		eax, 6			; SYS_CLOSE
	int		0x80
	ret

; =====================
; === SOCKET ERRORS ===
; =====================

_socket_fail:
	mov     ecx, sock_err_msg
	mov     edx, sock_err_msg_len
	call    _fail

_bind_fail:
	mov     ecx, bind_err_msg
	mov     edx, bind_err_msg_len
	call    _fail

_listen_fail:
	mov     ecx, lstn_err_msg
	mov     edx, lstn_err_msg_len
	call    _fail

_accept_fail:
	mov     ecx, accept_err_msg
	mov     edx, accept_err_msg_len
	call    _fail

_connect_fail:
	mov     ecx, conn_err_msg
	mov     edx, conn_err_msg_len
	call    _fail

_fail:
	mov		eax, 4 	; SYS_WRITE
	mov		ebx, 2	; STDERR
	int		0x80

	call	_exit

_exit:
	mov        eax, [sock]		; Check if socket fd is open
	cmp        eax, 0
	je         perform_exit
	call       _close_sock

	perform_exit:
	mov			eax, 1			; Exit syscall. thanks andrew
	mov			ebx, 1			; Miss me with that libc
	int			0x80
	ret

