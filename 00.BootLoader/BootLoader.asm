[ORG 0x00]	; 코드의 시작 어드레스를 0x00으로 설정
[BITS 16]	; 이하의 코드는 16비트 코드로 설정

SECTION .text	; text 섹션(세그먼트) 정의

jmp 0x07C0:START	; CS 세그먼트 레지스터에 0x07C0을 복사하면서, START 레이블로 이동
					; BIOS는 메모리 주소 0x07C00에 부트 로더를 복사한다.
					; 부트로더는 512바이트짜리 코드이므로 코드 영역을 0x07C00으로 설정한다

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;	MINT64 OS에 관련된 환경 설정 값
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
TOTALSECTORCOUNT:	dw	0x0	; 부트 로더를 제외한 MINT64 OS 이미지의 크기
							; 최대 1152 섹터까지 가능

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;	코드 영역
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

START:
	mov ax, 0x07C0	; 부트 로더의 시작 어드레스(0x7C00)를 세그먼트 레지스터 값으로 변환
	mov ds, ax		; DS 세그먼트 레지스터(데이터 영역 레지스터)에 설정
	mov ax, 0xB800	; 비디오 메모리(화면 출력)의 시작 어드레스(0xB8000)를 세그먼트 레지스터 값으로 변환
	mov es, ax		; ES 세그먼트 레지스터(문자열 관련 레지스터)에 설정

	;스택을 0x0000:0000~0x0000:FFFF 영역에 64KB(0x10000) 크기로 생성
	mov ax, 0x0000	; 스택 세그먼트의 시작 어드레스(0x0000)를 세그먼트 레지스터 값으로 변환
	mov ss, ax		; SS 세그먼트 레지스터(스택 기준주소 저장)에 설정
	mov sp, 0xFFFE	; SP 레지스터의 어드레스를 0xFFFE로 설정
	mov bp, 0xFFFE	; BP 레지스터의 어드레스를 0xFFFE로 설정

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	화면을 모두 지우고, 속성 값을 녹색으로 설정
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	mov si, 0	; SI 레지스터(원본 문자열 인덱스 레지스터)를 초기화

.SCREENCLEARLOOP:
	mov byte[es:si], 0		; 화면을 지우는 루프
							; 비디오 메모리의 문자가 위치하는 어드레스에
							; 0을 복사하여 문자를 삭제
	mov byte[es:si+1], 0x0A	; 비디오 메모리의 속성이 위치하는 어드레스에
							; 0x0A(검은 바탕에 밝은 녹색)을 복사
	add si, 2
	cmp si, 80 * 25 * 2		; 화면의 전체 크기는 80문자 * 25라인
							; 출력한 문자의 수를 의미하는 SI 레지스터와 비교
	jl .SCREENCLEARLOOP		; SI 레지스터가 80*25*2보다 작다면 아직 지우지
							; 못한 영역이 있으므로 .SCREENCLEARLOOP 레이블로 이동

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	화면 상단에 시작 메시지 출력
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	mov si, 0
	push MESSAGE1; 출력할 메시지의 어드레스를 스택에 삽입
	call PRINTMESSAGE	; PRINTMESSAGE 함수 호출
	add sp, 4 		; 삽입한 파라미터 제거
	call SPLIT_LINE
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	화면 상단에 현재 날짜 출력
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	push CURRENTDATEMESSAGE
	call PRINTMESSAGE
	add sp, 4

.GETREALTIME:
	mov ah, 04h
	int 1Ah

	;일자 출력
	movzx ax, dl
	push ax
	call PRINT_BCD
	add sp, 4

	mov byte[es:di], '/'
	add di, 2

	;달 출력
	movzx ax, dh
	push ax
	call PRINT_BCD
	add sp, 4

	mov byte[es:di], '/'
	add di, 2

	;연도 출력;
	movzx ax, ch
	push ax
	call PRINT_BCD
	add sp, 4
	movzx ax, cl
	push ax
	call PRINT_BCD
	add sp, 4

	;요일 출력
;	call PRINT_DAY

	call SPLIT_LINE

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	OS 이미지를 로딩한다는 메시지 출력
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	push IMAGELOADINGMESSAGE	; 출력할 메시지의 어드레스를 스택에 삽입
	call PRINTMESSAGE			; PRINTMESSAGE 함수 호출
	add sp, 4				; 삽입한 파라미터 제거

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	디스크에서 OS 이미지를 로딩
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	디스크를 읽기 전에 먼저 리셋
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

RESETDISK:					;디스크를 리셋하는 코드의 시작
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	BIOS Reset Function 호출
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	; 서비스 번호 0, 드라이브 번호(0=Floppy)
	mov ax, 0
	mov dl, 0
	int 0x13
	; 에러가 발생하면 에러 처리로 이동
	jc HANDLEDISKERROR

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	디스크에서 섹터를 읽음
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	; 디스크의 내용을 메모리로 복사할 어드레스(ES:BX)를 0x10000으로 설정
	mov si, 0x1000			; OS 이미지를 복사할 어드레스(0x10000)를
							; 세그먼트 레지스터 값으로 변환
	mov es, si				; ES 세그먼트 레지스터에 값 설정
	mov bx, 0x0000			; BX 레지스터에 0x0000을 설정하여 복사할
							; 어드레스를 0x1000:0000(0x10000)으로 최종 설정

	mov di, word[TOTALSECTORCOUNT]	; 복사할 OS 이미지의 섹터 수를 DI 레지스터에 설정

READDATA:					;디스크를 읽는 코드의 시작
	; 모든 섹터를 다 읽었는지 확인
	cmp di, 0		; 복사할 OS 이미지의 섹터 수를 0과 비교
	je READEND		; 복사할 섹터 수가 0이라면 다 복사 했으므로 READEND로 이동
	sub di, 0x1		; 복사할 섹터 수를 1 감소

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	BIOS Read Function 호출
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	mov ah, 0x02				; BIOS 서비스 번호 2(Read Sector)
	mov al, 0x1					; 읽을 섹터 수는 1
	mov ch, byte[TRACKNUMBER]	; 읽을 트랙 번호 설정
	mov cl, byte[SECTORNUMBER]	; 읽을 섹터 번호 설정
	mov dh, byte[HEADNUMBER]	; 읽을 헤드 번호 설정
	mov dl, 0x00				; 읽을 드라이브 번호(0=Floppy) 설정
	int 0x13					; 인터럽트 서비스 수행
	jc HANDLEDISKERROR			; 에러가 발생했다면 HANDLEDISKERROR로 이동

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	복사할 어드레스와 트랙, 헤드, 섹터 어드레스 계산
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	add si, 0x0020	; 512(0x200)바이트만큼 읽었으므로, 이를 세그먼트 레지스터 값으로 변환
	mov es, si		; ES 세그먼트 레지스터에 더해서 어드레스를 한 섹터 만큼 증가

	; 한 섹터를 읽었으므로 섹터 번호를 증가시키고 마지막 섹터까지 읽었는지 판단
	; 마지막 섹터가 아니면 섹터 읽기로 이동해서 다시 섹터 읽기 수행
	mov al, byte[SECTORNUMBER]		; 섹터 번호를 AL 레지스터에 설정
	add al, 0x01					; 섹터 번호를 1 증가
	mov byte[SECTORNUMBER], al		; 증가시킨 섹터 번호를 SECTORNUMBER에 다시 설정
	cmp al, 19						; 증가시킨 섹터 번호를 19와 비교
	jl READDATA						; 섹터 번호가 19 미만이라면 READDATA로 이동

	; 마지막 섹터까지 읽었으면(섹터 번호가 19이면) 헤드를 토글(0->1, 1->0)하고,
	; 섹터 번호를 1로 설정
	xor byte[HEADNUMBER], 0x01		; 헤드 번호를 0x01과 XOR 하여 토글(0->1, 1->0)
	mov byte[SECTORNUMBER], 0x01	; 섹터 번호를 다시 1로 설정

	; 만약 헤드가 1->0으로 바뀌었으면 양쪽 헤드를 모두 읽은 것이므로
	; 아래로 이동하여 트랙 번호를 1 증가
	cmp byte[HEADNUMBER], 0x00		; 헤드 번호를 0x00과 비교
	jne READDATA					; 헤드 번호가 0이 아니면 READDATA로 이동

	; 트랙을 1 증가시킨 후 다시 섹터 읽기로 이동
	add byte[TRACKNUMBER], 0x01		; 트랙 번호를 1 증가
	jmp READDATA					; READDATA로 이동
READEND:

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	OS이미지가 완료되었다는 메시지를 출력
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	push LOADINGCOMPLETEMESSAGE		; 출력할 메시지의 어드레스를 스택에 삽입
	call PRINTMESSAGE				; PRINTMESSAGE 함수 호출
	add sp, 4						; 삽입한 파라미터 제거

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;	로딩한 가상 OS 이미지 실행
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	jmp 0x1000:0x0000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;	함수 코드 영역
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 디스크 에러를 처리하는 함수
HANDLEDISKERROR:
	push DISKERRORMESSAGE	; 에러 문자열의 어드레스를 스택에 삽입
	call PRINTMESSAGE		; PRINTMESSAGE 함수 호출
	add sp, 4

	jmp $					; 현재 위치에서 무한 루프 수행

; 메시지를 출력하는 함수
; PARAM: x 좌표, y 좌표, 문자열
SPLIT_LINE:
	push si
	mov si, di
	mov di, 0
	.LOOPFORSPLIT_LINE:
		sub si, 160
		add di, 160
		cmp si, 0
		jge .LOOPFORSPLIT_LINE
	pop si
	ret
PRINTMESSAGE:
	push bp		; 베이스 포인터 레지스터(BP)를 스택에 삽입
	mov bp, sp	; 베이스 포인터 레지스터(BP)에 스택 포인터 레지스터(SP)의 값을 설정
				; 베이스 포인터 레지스터를 이용해서 파라미터에 접근할 목적
	push si		; 함수에서 임시로 사용하는 레지스터로 함수의 마지막 부분에서
	push ax		; 스택에 삽입된 값을 꺼내 원래 값으로 복원
	push cx
	push dx
	mov si, word[bp+4]		; 파라미터 3(출력할 문자열의 어드레스)
.MESSAGELOOP:				; 메시지를 출력하는 루프
	mov cl, byte[si]		; SI 레지스터가 가리키는 문자열의 위치에서 한 문자를
							; CL 레지스터에 복사
							; CL 레지스터는 CX 레지스터의 하위 1바이트를 의미
	cmp cl, 0				; 복사된 문자와 0을 비교
	je .MESSAGEEND			; 복사한 문자의 값이 0이면 문자열이 종료되었음을 의미하므로
							; .MESSAGEEND로 이동하여 문자 출력 종료

	mov byte[es:di], cl		; 0이 아니라면 비디오 메모리 어드레스 0xB800:di에 문자를 출력

	add si, 1				; SI 레지스터에 1을 더하여 다음 문자열로 이동
	add di, 2				; DI 레지스터에 2를 더하여 비디오 메모리의 다음 문자 위치로 이동
							; 비디오 메모리는 (문자, 속성)의 쌍으로 구성되므로 문자만 출력하려면
							; 2를 더해야 함

	jmp .MESSAGELOOP		; 메시지 출력 루프로 이동하여 다음 문자를 출력

.MESSAGEEND:
	pop dx					; 함수에서 사용이 끝난 DX 레지스터부터 ES 레지스터까지를
	pop cx					; 스택에 삽입된 값을 이용해서 복원
	pop ax					; 스택은 가장 마지막에 들어간 데이터가 가장 먼저 나오는
	pop si					; LIFO 자료구조이므로 삽입의 역순으로 제거(pop)해야 한다.
	pop bp					; 베이스 포인터 레지스터(BP) 복원
	ret						; 함수를 호출한 다음 코드의 위치로 복귀

PRINT_BCD:
	push bp		; 베이스 포인터 레지스터(BP)를 스택에 삽입
	mov bp, sp	; 베이스 포인터 레지스터(BP)에 스택 포인터 레지스터(SP)의 값을 설정
				; 베이스 포인터 레지스터를 이용해서 파라미터에 접근할 목적
	push si
	push ax
	push bx
	push cx
	push dx

	movzx cx, byte[bp+4]

	mov bx, cx
	shl bx, 4
	and bh, 0fh
	add bh, '0'
	mov byte[es:di], bh
	add di, 2
	shr bx, 4
	and bl, 0fh
	add bl, '0'
	mov byte[es:di], bl
	add di, 2

	pop dx					; 함수에서 사용이 끝난 DX 레지스터부터 ES 레지스터까지를
	pop cx
	pop bx					; 스택에 삽입된 값을 이용해서 복원
	pop ax					; 스택은 가장 마지막에 들어간 데이터가 가장 먼저 나오는
	pop si					; LIFO 자료구조이므로 삽입의 역순으로 제거(pop)해야 한다.
	pop bp					; 베이스 포인터 레지스터(BP) 복원
	ret						; 함수를 호출한 다음 코드의 위치로 복귀
; PRINT_DAY:
; 	push bp
; 	mov bp, sp

; 	mov bx, 0	; 지난 날짜

; 	push dl
; 	call BCD_TO_NUM
; 	add sp, 2
; 	push bx		; 일을 스택에 저장한다

; 	push dl
; 	call BCD_TO_NUM
; 	add sp, 2
; 	push bx		; 월을 스택에 저장한다

; 	pop bx
; 	pop bp
; 	ret
; CALCULATE_YEAR:
; 	mov bx, 0
; 	push ch		; 연도 더하기	
; 	call BCD_TO_NUM
; 	add sp, 2
; 	add bx, ax
; 	mul bx, 100
; 	push cl
; 	call BCD_TO_NUM
; 	add sp, 2
; 	add bx, ax

; 	sub bx, 1	; 작년까지의 기간 Pre Year
; 	push bx		; 년을 스택에 저장한다

; 	mov cx, 0	; num of days = 
; 	mov dx, 0
; 	mov ax, bx	
; 	div ax, 4	; + year/4
; 	add cx, ah
; 	mov ax, bx
; 	div ax, 400	; + year/400
; 	add cx, ah
; 	mov ax, bx
; 	div ax, 100	; - year/100
; 	sub cx, ah

; 	pop bx
; 	mul bx, 365
; 	add bx, cx
; 	ret
; CALCULATE_MONTH:
; CALCULATE_DATE:
; BCD_TO_NUM:					; bcd를 숫자로 바꾸는 함수
; 	push bp
; 	mov bp, sp
; 	push bx

; 	movzx cx, byte[bp+2]
; 	mov ax, 0
; 	mov bx, cx
; 	shl bx, 4
; 	and bh, 0fh
; 	mul bh, 10
; 	add ax, bh
; 	shr bx, 4
; 	and bl, 0fh
; 	add ax, bh

; 	pop bx
; 	pop bp
; 	ret 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;	데이터 영역
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 부트 로더 시작 메시지
MESSAGE1:	db 'MINT64 OS Boot Loader Start~!!', 0	; 출력할 메시지 정의
DISKERRORMESSAGE:		db 'DISK ERROR~!!', 0		; 마지막은 0으로 설정하여 .MESSAGELOOP에서
IMAGELOADINGMESSAGE:	db 'OS Image Loading...', 0 ; 문자열이 종료되었음을 알 수 있도록 함
LOADINGCOMPLETEMESSAGE:	db 'Complete~!!', 0
CURRENTDATEMESSAGE: 	db 'Current Data: ',0

; 디스크 읽기에 필요한 변수들
SECTORNUMBER		db 0x02	; OS 이미지가 시작하는 섹터 번호를 저장하는 영역
HEADNUMBER			db 0x00	; OS 이미지가 시작하는 헤드 번호를 저장하는 영역
TRACKNUMBER			db 0x00	; OS 이미지가 시작하는 트랙 번호를 저장하는 영역

times 510-($ - $$)	db 0x00

db 0x55
db 0xAA
