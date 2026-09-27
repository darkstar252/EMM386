;*****************************************************************************
;**                  c't  --  magazin fuer computer technik                 **
;*****************************************************************************
;**                     Release   08/90   from page  214                    **
;**                                                                         **
;** original author and copyright                                           **
;**   (c) 1990       c't/Harald Albrecht                                    **
;**   (c) 2001-2004  tom ehlert                                             **
;**                                                                         **
;**	Licensed under the Artistic License version                             **
;**	                                                                        **
;**	please see LICENSE.TXT for details                                      **
;**                                                                         **
;*****************************************************************************
;**                                                                         **
;** original author and copyright                                           **
;**   (c) 1990 c't/Harald Albrecht                                          **
;**                                                                         **
;** created the v86 monitor part and EMS functions                                                                        **
;**                                                                         **
;**                                                                         **
;**        1990 Thomas Gloeckler - Rechenzentrum FH Ulm                     **
;** significant enhancements (DMA+fixes)                                    **
;**                                                                         **
;**                                                                         **
;** put into current shape as a potential EMM386 (EMM386-VCPI-DPMI-...)     **
;**   (c)  2001  junk@drivesnapshot.de                                      **
;**                                                                         **
;** implemented VCPI                                                        **
;**        2004 michael devore                                              **
;**                                                                         **
;**                                                                         **
;**  for better understanding of the code history                           **                                     **
;**                                                                         **
;**  lowercase                                                              **
;**  	mov ax,bx                                                           **
;**  and english comments are my (tom ehlert) contribution                  **
;**                                                                         **
;**  UPPER case                                                             **
;**     MOV AX,BX                                                           **
;**  and german comments are generally the original (c't / Harald Albrecht) **
;**  where however                                                          **
;**  I may have cut/copy/pasted ... things around                           **
;**                                                                         **
;**                                                                         **
;**  11/23/2001  tom ehlert                                                 **
;**                                                                         **
;**																			**
;**  30/10/2003	  Imre Leber												**
;**																			**
;**				   All German strings finally translated to English			**
;**				   Merged code from Eric Auer								**
;**																			**
;**  12/2003      Michael Devore                                            **
;**                                                                         **
;** - Modified for >64M and VCPI support
;** - Updated for EMS 4.0, some extended API returns unsupported, this will
;**   change as requested or needed by other software requirements
;** - Documented EMS 4.0 only supports up to 32M (0x800 pages), but some EMS
;**   drivers allow more than 32M.  The EMS 4.0 spec could be extended to 1G-32K
;**   (map value of 0xFFFF means unmap) without breaking the spec API.
;**   I have arbitrarily decided to allow up to 480M of EMS allocations,
;**   leaving the high bit of page allocation alone since specific drivers
;**   may make use of high bit values other than 0xFFFF for their own purposes,
;**   or may only check high bit for unmap -- as FreeDOS EMM386 does.
;**   480M allows easy alignment of tables to 4K for VCPI, although 511M
;**   could be supported without VCPI or even with VCPI with additional work.
;**	- Minor English corrections where useful for comprehension              **
;**                                                                         **
;**   Michael Devore's changes are not copyrighted and are released
;**   to the public domain.
;**   This does not affect copyright on the rest of the code.
;**                                                                         **
;**																			**
;*****************************************************************************
                TITLE   V86 - Virtual 8086-Monitor for 80386 PCs
		NAME    V86
;
;                          V 8 6        Version 1.34


;
; (c) 1990 c't/Harald Albrecht
; (c) 2001 tom.ehlert@ginko.de
;
;     T A S M 1.0 / 1.01
;     TC 2.01
;
; Virtual 8086-Monitor, that puts the pc after booting into virtual
; 8086-working mode.
; **** #### Changes of V1.4 against (magazine version) V1.3 are
; **** #### marked by this, there are also:
; **** #### additional questions/questioning with the installation on EMMXXXX0,
; **** #### because some BIOS's take ownership of INT67
; **** #### Failure when asking after the mark 'ct' means (eliminated)
; **** #### that Extended Memory doesn't use now the full capacity,
; **** #### using EXT you can provide the rest of the extended memory
; **** #### STack as Classname for Stack-Segmenr for TLINK 3.0
;
; As a result of using the appropriate extensions in the places marked with (* - 1 - *)
; and so on arises:
;
;**** ####  E M M    Version 1.4
;           LIM-EMS-Driver for 386 PCs (EMS Version 3.2)
;
; (c) 1989 Harald Albrecht
;
;(#-0-#)
; By utilising the extensions (#-1-#) and on, DMA support is installed.
;
;       DMA-support &  The savage thirteen     Version 1.0
;
; (c) 1990 Harald Albrecht
;(#-0-#)
;
		.486P
        .SEQ  		                       ; Absolutely keep row-order/sequence of the Segment-
                                             ; Definitions!!!

		public _MAXPAGES
		public _PAGESAVAIL
		public _FRAME
		public _NoVCPI
		public _FlagNOEMS
		public _NoPageFrame
		public _SB
		public _AltBoot
		public _startup_verbose

		LOCALS

LF              EQU 0AH
CR              EQU 0DH

V86_TOS         EQU 200H             ; Size of monitor stack

; **** ##### changed to ggf keep space free in Extended Memory
EXT             EQU 14*1024                  ; here you can enter the
                                             ; optional size in KB

; 4K+2K multiple required here, so that that internal EMSPAGETABLE at
; alignment 2K (1 byte per page) is 4K aligned for later VCPI allocations
MAX_EMS_PAGES_ALLOWED	EQU	(7*4096)+2048	; 480M max mem (16K each page)

UNIMPLEMENTED_EMS_DEBUG	EQU	0
VCPI_DEBUG	EQU	0


PORT_A          EQU 60H              ; Data-port of the 8042
STATUS_PORT     EQU 64H              ; Statusport of the 8042

@KB_FLAG        EQU 417H             ; Status SHIFT/CTRL/ALT etcetera.
@KB_FLAG_3      EQU 496H             ; u.a. 0E0h/0E1h
@RESET_FLAG     EQU 472H             ; Flag for Warmboot (=1234h)

; GDT - Selectors in the Global Descriptor Table GDT
NULL_SEL        EQU 00H              ; Null-Descriptor
V86_LDT_SEL     EQU 08H              ; Local Descriptor Table Selector
V86_TSS_SEL     EQU 10H              ; Task State Segment of the Monitor
TMP_TSS_SEL     EQU 18H              ; Shorttime needed TSS (0th TSS, will
		; be filled by waste data when activating the 1st real TSS)
REAL_SEL        EQU 20H              ; CS for return to real mode
REAL_DATA_SEL   EQU 28H              ; DS for return to real mode
UNIVERSE_SEL    EQU 30H              ; 4-GByte-Data-segment
; GDT for stack segment makes debugging a lot easier
V86_STACK_SEL   EQU 38H              ; dto. Stack-Segment (STACK) ; = same?

; LDT - Selectors in the Local Descriptor Table
V86_CODE_SEL    EQU 0CH              ; Code-Segment virtual 86-Monitor
V86_DATA_SEL    EQU 14H              ; dto. Data-Segment (DATA) ; dto=ditto
;V86_STACK_SEL   EQU 1CH              ; dto. Stack-Segment (STACK) ; = same?

;(#-1-#)
DMA_BUFF_SIZE   EQU     64              ; DMA-Buffer size in kBytes

BasePrgrd       EQU      0              ; 0 - programmed Address
LenPrgrd        EQU      1              ; 0 - programmed Block length
PagePrgrd       EQU      2              ; 0 - programmed Page register
ModePrgrd       EQU      3              ; 0 - programmed Mode-register

INT13Activ      EQU      0              ; INT 13h is active
INT40Activ      EQU      1              ; INT 40h is active
NeedBuffer      EQU      2              ; DMA-Transfer via Buffer
HiLoFlag1       EQU     14              ; adressing the Hi-Byte , DMA #1
HiLoFlag2       EQU     15              ; Same for DMA controller #2

REPCMD  MACRO CMD,OP                     ;; Call Command with different
                IRP     OPERAND,<&OP>    ;; operands back
		CMD     OPERAND
		ENDM
		ENDM
;(#-1-#)

; Macro for bypassing the 386-Bug with 32-Bit-Stringoperations
; only needed for Mask-version B3
; AddressSize - Prefix + NOP attached

BIG_NOP MACRO
		DB 67h    ;  32-Bit-Prefix
		NOP
		ENDM
;
;
; Macro for describing the Descriptors
;
SELECTOR MACRO BEGIN,LIMIT,ACCESS,GRANULARITY
                DW      LIMIT                   ;; Size of Segment (15..0)
                DW      BEGIN                   ;; Start of Segment (15..0)
                DB      0                       ;; Beginning (23..16)
		DB      ACCESS
                DB      GRANULARITY             ;; u.a. Size (19..16)
                DB      0                       ;; Beginning (31..24)
		ENDM

; VCPI switch from V86 to protected mode data structure
SWSTR	STRUC
	SW_CR3		DD	?	; client's CR3 value
	SW_GDTOFFS	DD	?	; offset of client's GDTR value
	SW_IDTOFFS	DD	?	; offset of client's IDTR value
	SW_LDTR		DW	?	; client's LDTR value
	SW_TR		DW	?	; client's TR value
	SW_EIP		DD	?	; entry point in client
	SW_CS		DW	?
SWSTR	ENDS


DRIVERCODE SEGMENT PARA USE16
DRIVERCODE ENDS


; The stack remains in any case resident, because it's needed during the return
; to REAL-Mode for the termination of the errorsolving
; process(es).

; no return to realmode ever wanted, no res_stack
RES_STACK  SEGMENT  PARA USE16
        DB      V86_TOS DUP (?)  ; space for Stack
;TOS     LABEL   WORD
RES_STACK  ENDS


RESCODE SEGMENT PARA USE16
RESCODE ENDS

; some versions TLINK place this out of order if simply named DATA
MONDATA    SEGMENT PARA USE16
MONDATA    ENDS

CODE    SEGMENT PARA USE16
CODE 	ENDS

V86     SEGMENT PARA USE16
V86 	ENDS

_TEXT	segment	PARA public 'CODE' use16
_TEXT	ends

_DATA	segment word public 'DATA' use16
_DATA	ends

_BSS	segment word public 'BSS'  use16
_BSS	ends

_STACK	segment STACK  'STACK' use16
_STACK	ends

DGROUP	group	_DATA,_BSS,_STACK


TMP_STACK SEGMENT STACK PARA USE16
TMP_STACK ENDS


DRIVERCODE SEGMENT PARA USE16
		ASSUME  CS:DRIVERCODE,DS:NOTHING,ES:NOTHING,FS:NOTHING,GS:NOTHING

;******************************************************************************
; device driver header

device_header:
		dd  -1			    ; last driver in list
		dw  0c000h		    ; driver flags :
					    ; 8000 - character device
					    ; 4000 - supports IOCTL - like EMM386
		dw  offset strategy	    ; pointer to strategy routine
		dw  offset interrupt	    ; pointer to interrupt handler
_EMM_Driver_Name:
		db  'EMMXXXX0'		    ; device driver name



;******************************************************************************
; strategy routine. is called by DOS to initialize the driver once.
; only thing to be done here is to store the address of the device driver
; request block.
; In:   ES:BX - address of request header
; Out:  nothing

public interrupt,strategy,device_header,_EMM_Driver_Name

request_ptr dd  0			    ; pointer to request header

strategy:
	mov word ptr cs:[request_ptr+2],es  ; store segment addr
	mov word ptr cs:[request_ptr],bx    ; store offset addr
	retf				    ; far return here!

interrupt:
	;int 3			; trigger driver entry for debugging purpose

	push es
	push di

	les di,cs:[request_ptr]          ; load address of request header

	cmp byte ptr es:[di+2],3          ; AH=03h: IOCTL Input ("Read from
	je  short do_ioctl_input          ; Control Channel" - por aqui pide
							   ; Windows la estructura GEMMIS)

					; this driver assumes, it is called once
					; with cmd = INIT
					;
					; this one request is fullfilled, then
					; every other denied
	mov          es:[di+0eh+2],cs    ; set end address
	mov word ptr es:[di+0eh  ],0	 ;
	mov word ptr es:[di+3	 ],0800h ; STATUS_OK


	call far ptr go_driver_entry	 ; this will be patched
					 ; away after init
					 ; so ALL following request are simply OK'ed

	pop di
	pop es
	retf

do_ioctl_input:
	call	GEMMIS_ioctl_input	; es:di sigue apuntando a la cabecera
	pop	di
	pop	es
	retf

;*********************************************************
; GEMMIS (Global EMM Import Specification) - lo que Windows usa para
; saber qué zonas de memoria alta gestionamos nosotros (para "importar-
; las") y cuáles puede tratar como memoria física normal.
;
; No es un canal INT67h - Windows lo pide abriendo el dispositivo
; "EMMXXXX0" y haciendo un IOCTL Input (comando 3) con un byte de
; subfunción en su buffer. Referencia: implementación GPL de GEMMIS en
; DOSBox (src/ints/ems.cpp) - no existe documentación pública oficial
; de Microsoft para esto, así que toda la parte de "qué construir" viene
; de ahí, adaptada a las estructuras internas de ESTE EMM386 (que son
; distintas de las de DOSBox).
;
; IMPORTANTE: este código corre en modo real, llamado por DOS desde
; "interrupt:". Pero el estado real del EMS (FRAME, tabla de páginas,
; handles...) vive en el espacio de 32 bits del monitor V86, así que en
; vez de leer esas variables directamente (que aquí no significarían lo
; que parecen) se piden con llamadas normales a INT 67h - exactamente
; igual que lo haría cualquier programa que use EMS. Esto funciona
; porque este código solo se ejecuta bien entrado el arranque, con el
; monitor ya activo y el vector de INT 67h ya enganchado.
;*********************************************************

GEMMIS_VERSION		EQU	1
GEMMIS_STRUC_SIZE	EQU	019Dh

public GEMMIS_buf
GEMMIS_buf	db	GEMMIS_STRUC_SIZE dup(0)

;------------------------------------------------------------------------
; despacha la petición IOCTL según el byte de subfunción que Windows deja
; en su propio buffer (apuntado por la petición en es:[di+0Eh], con
; es:[di+12h] = número de bytes de ese buffer).
;
; In:	es:di -> cabecera de la petición de DOS
GEMMIS_ioctl_input PROC NEAR
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	ds

	lds	si, dword ptr es:[di+0eh]	; ds:si -> buffer del llamador
	mov	al, [si]			; subfunción pedida por Windows

	cmp	al, 0
	je	short @@sub0
	cmp	al, 1
	je	short @@sub1
	cmp	al, 2
	je	short @@sub2
	cmp	al, 3
	je	short @@sub3

	pop	ds				; subfunción desconocida
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	mov	word ptr es:[di+3], 8003h	; STATUS_ERROR | "unknown command"
	ret

@@sub0:
	mov	word ptr [si], 23h		; ID fijo que espera Windows
	mov	dword ptr [si+2], 0		; sin API privada propia
	jmp	short @@ok

@@sub1:
	call	GEMMIS_build			; rellena GEMMIS_buf con el estado
						; actual (vía INT67h, ver arriba)
	mov	word ptr [si], GEMMIS_VERSION
	mov	word ptr [si+2], offset GEMMIS_buf
	mov	word ptr [si+4], cs
	jmp	short @@ok

@@sub2:
	mov	ah, 46h
	int	67h				; al = versión EMM (formato BCD,
						; igual que devuelve GET_VERSION)
	mov	[si], ax
	jmp	short @@ok

@@sub3:
	mov	ah, 42h
	int	67h				; dx = páginas máximas totales
	mov	ax, dx
	shl	ax, 4				; páginas de 16Kb -> Kb
	mov	[si], ax			; tamaño máximo en Kb
	mov	word ptr [si+2], 0		; tamaño mínimo: no se exige ninguno

@@ok:
	pop	ds
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	mov	word ptr es:[di+3], 0800h	; STATUS_OK
	ret
GEMMIS_ioctl_input ENDP

;------------------------------------------------------------------------
; construye la estructura GEMMIS (413 bytes) en GEMMIS_buf, en el propio
; segmento del driver (no hace falta pedir memoria nueva: el driver ya
; está siempre residente).

GEMMIS_build PROC NEAR
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es

	push	cs
	pop	es
	mov	di, offset GEMMIS_buf

	mov	word ptr es:[di+0], 4			; flags: solo información EMS
	mov	word ptr es:[di+2], GEMMIS_STRUC_SIZE
	mov	word ptr es:[di+4], GEMMIS_VERSION
	mov	word ptr es:[di+6], 0			; reservado (dword)
	mov	word ptr es:[di+8], 0

;--- tabla de descriptores de frame: un registro de 6 bytes por cada
;--- 16Kb de espacio de direcciones entre 0 y 0F0000h. Todo lo que no
;--- sea la ventana EMS se marca como "no es EMS, mapeo directo" -
;--- Windows puede tratarlo como memoria física normal sin pedirnos
;--- permiso. AH=41h (ya existente en este EMM386) da el segmento de la
;--- ventana EMS sin tener que leer _FRAME directamente.

	mov	ah, 41h
	int	67h				; bx = segmento de la ventana EMS
	mov	ax, bx
	shr	ax, 6				; segmento / 400h -> índice de 16Kb
	mov	dx, ax
	add	dx, 4				; la ventana EMS ocupa 4 páginas de 16Kb

	mov	si, di
	add	si, 0Ah				; primer descriptor de frame
	xor	cx, cx				; cx = índice de descriptor actual
@@frame_loop:
	cmp	cx, ax				; ¿dentro de la ventana EMS?
	jb	short @@not_ems
	cmp	cx, dx
	jae	short @@not_ems

	mov	byte ptr es:[si+0], 3		; tipo: ventana EMS (64Kb)
	mov	byte ptr es:[si+1], cl		; número de página física EMS (0..3)
	mov	word ptr es:[si+2], 0		; sin uso para este tipo
	mov	byte ptr es:[si+4], 0		; propietario: nosotros
	mov	byte ptr es:[si+5], 0		; sin flags especiales
	jmp	short @@next_frame

@@not_ems:
	mov	byte ptr es:[si+0], 0		; tipo: NINGUNO (no es EMS)
	mov	byte ptr es:[si+1], 0ffh	; propietario: NINGUNO
	mov	word ptr es:[si+2], 0ffffh	; no es una página EMS
	mov	byte ptr es:[si+4], 0
	mov	byte ptr es:[si+5], 0aah	; mapeo directo

@@next_frame:
	add	si, 6
	inc	cx
	cmp	cx, 60				; 60 x 16Kb = 0F0000h
	jb	short @@frame_loop

;--- byte "misterioso" en el offset fijo 018Ah: ni siquiera la propia
;--- implementación de referencia (DOSBox, GPL) sabe qué codifica, pero
;--- hay que ponerlo igual porque forma parte del formato que espera
;--- Windows.

	mov	byte ptr es:[di+018Ah], 74h

;--- sin descriptores de UMB (0 = ninguno). DECISIÓN FINAL, no un
;--- pendiente: el valor numérico de "Type" para "esto es un frame UMB"
;--- no está confirmado en ningún sitio público que se pueda verificar
;--- (ni la especificación real de Microsoft, ni el EMMIMP.H que la
;--- acompañaba, están disponibles; ni siquiera DOSBox, la única
;--- implementación abierta que existe, los rellena de verdad - también
;--- reporta 0 siempre). Reportar 0 es lo que hace en producción la
;--- referencia que tenemos, así que es una decisión honesta y con
;--- precedente real, no una que se haya dejado a medias.

	mov	byte ptr es:[di+018Bh], 0

;--- un único registro de handle EMS: el handle 0 ("de sistema").
;--- AH=4Ch da el número de páginas correctamente (misma API pública
;--- que usaría cualquier programa). La dirección física NO se puede
;--- pedir por la API EMS estándar - no existe esa función, ni en este
;--- EMM386 ni en la especificación EMS en general, así que si el
;--- handle 0 tuviera páginas (en este driver normalmente tiene 0) se
;--- reporta dirección 0: es una limitación conocida y documentada, no
;--- un dato inventado.

	mov	byte ptr es:[di+018Ch], 1	; 1 registro de handle
	mov	word ptr es:[di+018Dh], 0	; número de handle = 0 (sistema)
	mov	dword ptr es:[di+018Fh], 0	; nombre del handle (sin nombre)
	mov	dword ptr es:[di+0193h], 0

	mov	dx, 0
	mov	ah, 4ch
	int	67h				; bx = páginas del handle 0
	mov	word ptr es:[di+0197h], bx
	mov	dword ptr es:[di+0199h], 0	; dirección física: ver nota arriba

	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
GEMMIS_build ENDP

;*********************************************************
; an UMB handler
; good enough for FreeDOS=UMB, for nothing else :-)
;*********************************************************

public _UMBhandler, _UMBOldhandler

_UMBhandler:

	jmp short TheUMBHandler			    ; standard XMS link chain
	nop					    ; with 3 required NOPs
	nop
	nop
TheUMBHandler:
	cmp ah,4				    ; global disable A20
	je  global_disable_a20
	cmp ah,6				    ; local disable A20
	je  local_disable_a20

	cmp ah,010h				    ; UMBallocate
	je  UMBallocate				    ;
	cmp	ah,11h				; UMB free
	je	UMBfree
						    ; else let the others return
						    ; 'not implemented'


not_for_us:
	db 0eah					    ; jmp far  UMBoldhandler
_UMBoldhandler dd 0



; dull and stupid - we neither reallocate nor free

;UMBfree:
;UMBreallocate:
;	mov bl,080h			; not implemented
;	mov ax,0			; failure
;	retf




;
;	REALLY dull and stupid - we manage exactly four UMB blocks
;   no UMBfree
;   no UMBrealloc
;   no largest size UMB size in alloc
;
;	but it's
;   feel free to do it better
;   this is filled in by C code
;
;
;extern struct {
;	ushort segment;
;	ushort size;
;	ulong  linearaddress_bottom;
;	ulong  linearaddress_top;
;	ulong  physical_offset;
;	} far UMBsegments[8];	/* UMB block 'array' :-) */


; allow up to 8 allocations of UMB's
public _UMBsegments
_UMBsegments	dd 0,0,0,0	; segment/size, linearaddress bottom, linear address 
                            ; top, phys. offset
		dd 0,0,0,0
		dd 0,0,0,0
		dd 0,0,0,0
		dd 0,0,0,0
		dd 0,0,0,0
		dd 0,0,0,0
		dd 0,0,0,0


UMBallocate:
	push	cx
	push	si

					; find first available memory block
	lea	bx, cs:[_UMBsegments]
	mov	cx,8			; ch flags any UMB found (in case too small), cl is entry count
	xor	si,si		; holds largest too-small block size

@@UMBloop:
	cmp	WORD PTR cs:[bx],0	; see if valid UMB
	je	@@UMBNext			; no
	test	BYTE PTR cs:[bx+3],80h	; see if UMB already allocated (high bit size set)
	jne	@@UMBnext			;  yes
	cmp	dx,cs:[bx+2]		; dx = requested block size (high bit of UMB size known reset)
	jbe	@@UMBfound			; enough memory available in UMB
	mov	ch,1				; flag UMB was found, although too small
	cmp	si,cs:[bx+2]
	ja	@@UMBnext
	mov	si,cs:[bx+2]		; update largest too-small block size

@@UMBnext:
	add	bx,16
	dec	cl
	jne	@@UMBloop
	or	ch,ch
	jne	umb_too_small
	jmp	no_umbs_available

@@UMBfound:

; see if actual UMB size exceeds request size by >=2K
	mov	ax,80h				; 128 paras == 2K
	add	ax,dx
	cmp	ax,cs:[bx+2]
	ja	good_umb			; can't split it, just use it

;  2K or over would be unused, see if we can split the block
	mov	cl,8
	lea	si,cs:[_UMBsegments]

@@splitloop:
	cmp	WORD PTR cs:[si],0
	jne	@@splitnext

; split the block
	mov	ax,dx
	add	ax,7fh
	and	ax,0ff80h			; round up allocation to next 2K in paras
	mov	cx,cs:[bx]
	add	cx,ax
	mov	cs:[si],cx			; new block has segment offset of old block+allocation
	mov	cx,cs:[bx+2]		; get original UMB block size, in paras
	sub	cx,ax				; subtract allocation
	mov	cs:[si+2],cx		; update new block with old block size minus allocation
	mov	cs:[bx+2],ax		; update original UMB block size to allocation

; if you're using VDS, you need to update the
;  linear and physical address of the new block and old block
;  but VDS doesn't work anyway, so I'm not going to do it now

	jmp	good_umb

@@splitnext:
	add	si,16
	dec	cl
	jne	@@splitloop

good_umb:
	mov	dx,cs:[bx+2]		; actual block size to dx
	or	BYTE PTR cs:[bx+3],80h	; flag UMB allocated
	mov	bx,cs:[bx]			; get UMB address in bx
	mov	ax,1
	pop	si
	pop	cx
	retf

umb_too_small:
	mov	bl,0B0h	; only smaller UMB available
	mov	dx,si

umb_badalloc:
	xor	ax,ax			; flag failure
	pop	si
	pop	cx
	retf

no_umbs_available:
	mov	bl,0B1h	; no UMB's are available
	xor	dx,dx
	jmp	umb_badalloc

UMBfree:
	push	bx
	push	cx
	mov	cl,8
	lea	bx,cs:[_UMBsegments]

@@freeloop:
	cmp	cs:[bx],dx		; see if matches existing UMB allocation
	jne	@@freenext
	and	BYTE PTR cs:[bx+3],7fh	; flag UMB not allocated
	mov	ax,1			; flag success
	pop	cx
	pop	bx
	retf

@@freenext:
	add	bx,16
	dec	cl
	jne	@@freeloop

	xor	ax,ax			; flag failure
	mov	bl,0b2h			; invalid UMB segment number error code
	pop	cx
	retf	2			; consume original bx on stack

;
; we do not want to have A20 disabled - we need it !
; so we don't do anything - and even say SUCCESS - like WinNT DOSBOX
;

global_disable_a20:
local_disable_a20:
	mov ax,1
	mov bl,0
	retf


if 1
;******************************************************
; absolute braindamaged VDS implementation - october 2002
;******************************************************
public _int4b_handler
public _int4b_oldhandler

_int4b_handler:
	cmp ah,081h
	je  vds_handler

	db 0eah
_int4b_oldhandler:
	dd 0

vds_error:
	push si
	push bx
	call print
	db 'unimplemented VDS function',0dh,0ah,0
	pop  bx
	pop si


	mov al,0fh			; function not supported
	sti
	stc
	retf 2

vds_handler:

	cmp al,3
	je	vds_lock
	jmp vds_error


;   DDS                   STRUCT
;     Region_Size         DWORD     ?    ; offset 0
;     Offset              DWORD     ?    ; offset 4
;     Seg_or_Select       WORD      ?    ; offset 8
;     Buffer_ID           WORD      ?    ; offset A
;     Physical_Address    DWORD     ?    ; offset C
;   DDS                   ENDS


vds_lock:

;	call print
;	db 'VDS lock',0dh,0ah,0


	push eax

	xor     eax,eax
	mov 	ax, es:[di+8];	segment
	shl	eax,4
	add	eax, es:[di+4]; offset


	push cx
	push bx
	mov  cx,4
	lea bx, _UMBsegments

vds_lock_loop:
	cmp eax, cs:[bx+4]
	jb	vds_lock_done

	cmp eax, cs:[bx+8]
	jb	vds_lock_found

	loop vds_lock_loop

vds_lock_found:
	add 	eax, cs:[bx+12]
vds_lock_done:
	mov	es:[di+0ch],eax ; physical address


	pop	bx
	pop	cx
	pop	eax


	sti
	clc
	retf 2

endif
;******************************************************
; end of absolute braindamaged VDS implementation - october 2002
;******************************************************







;*******************************************
; prints text after call
; we rely on DOS to satisfy INT 29
;*******************************************

__print proc near

print_1char:
	int 29h						  ; int29:  DOS 2+ - FAST CONSOLE OUTPUT
							  ; * al = char to display
							  ; * destroys bx

print2:	pop   bx
	pop   si                       ; this is the first character
	mov   al,cs:[si]               ; get token
	inc   si
	push  si			; stack up potential return address
	push  bx

	cmp   al, 0                    ; end of string?
	jne   print_1char              ; until done
	ret


print:
	call print2
	ret


;*******************************************
; printing routines
; we rely on DOS to satisfy INT 29
;
; print
;   db 'hello world'
;
; printdh,printdx - what the name implies
;
; printhex, printhexd
;   'ds=',0    'eax=',0
;
;*******************************************

printdx:
	call printdh
	ror  dx,8

printdh:
	call printnibble
printnibble:

	ror dh,4


	mov al,dh

	and al,0fh
	add al,'0'
	cmp al,'9'
	jbe nohex
	add al,'A'-'0' - 10
nohex:

	int 29h
	ret


printhex:
	call print2

	mov al,'='
	int 29h

printhex2:
	call printdx

	mov al,' '
	int 29h

	ret                            ; and jump to it


printhexd:
	call print2

	mov al,'='
	int 29h

        ror edx,16

	call printdx

        ror edx,16

        jmp printhex2


__print endp


;*********************************************************************
;
; illegal instruction executed
; print some diagnostic
; end program
;
; if int21/4c returns (during device init or more regularily
; for command.com), there is nothing left do to. show 'I am alive'
; and wait for '3FingerSalut'
;*********************************************************************

	public	_IllegalOpcodeHandler
_IllegalOpcodeHandler proc FAR

	; flags 36
	; CS    34
	; IP    32

	push es ;30
	push ds ;28
	push ebp ;24
	push edi ;20
	push esi ;16
	push edx ;12
	push ecx ;8
	push ebx ;4
	push eax ;0

	mov bp,sp
	push cs
	pop  ds


	call print
	db CR,LF,LF,'Illegal Instruction occurred',CR,LF,0


	mov dx,[bp+34]
	call printhex
	db 'CS',0

	mov dx,[bp+32]
	call printhex
	db 'IP',0

	mov dx,ss
	call printhex
	db 'SS',0

	mov dx,bp
	add dx, 38
	call printhex
	db 'SP',0

	mov dx,[bp+26]
	call printhex
	db 'DS',0

	mov dx,[bp+28]
	call printhex
	db 'ES',0


	mov edx,[bp]
	call printhexd
	db CR,LF,'EAX',0

	mov edx,[bp+4]
	call printhexd
	db 'EBX',0

	mov edx,[bp+8]
	call printhexd
	db 'ECX',0

	mov dx,[bp+12]
	call printhexd
	db 'EDX',0

	mov dx,[bp+16]
	call printhexd
	db CR,LF,'ESI',0

	mov dx,[bp+20]
	call printhexd
	db 'EDI',0


	mov dx,[bp+24]
	call printhexd
	db 'EBP',0

	call print
	db CR,LF,'Opcodes @CS:IP ',0

	les di,	[bp+32]		; CS:IP

	mov cx,8
hexdloop:
	push cx
	mov dh, es:[di]
	inc di
	call printdh
	call print
	db ' ',0
	pop cx
	loop hexdloop


	call print
	db CR,LF,'Aborting program',CR,LF,0

	sti
	mov ax,04c7fh
	int 21h

					; and if we tried to abort command.com
					; it will come back here
					; there is nothing left we can do, so
					; we do a dynamic halt, waiting for
					; Ctrl-Alt-Delete
	sub dx,dx
stopit: sti
	call printhex
	db CR,'EMM386 - unable to continue - Please reboot',0
	inc dx
	jmp stopit			; should never be executed

_IllegalOpcodeHandler	endp

DRIVERCODE ENDS

;*********************************************************************

RESCODE SEGMENT
		ASSUME  CS:RESCODE,DS:NOTHING,ES:NOTHING,FS:NOTHING,GS:NOTHING

RETURN_OF_THE_86 PROC FAR
        CLI								 ; No disturbance of the peace !
        MOV     AX,REAL_DATA_SEL         ; Load the On-Chip-Registercache of the
        MOV     DS,AX                    ; Segmentregister with the attributes
        MOV     ES,AX                    ; of REAL-Mode (who from now on
        MOV     FS,AX                    ; on wants to write MOV CS,AX
        MOV     GS,AX                    ; should be ashamed!)
	    MOV     SS,AX

        MOV     EAX,CR0                  ; read from CR0-Register, to
        AND     EAX,7FFFFFFEH            ; disable the PE- Bit (Protected Mode Enable)
        MOV     CR0,EAX                  ; and any possibly Paging.
        XOR     EAX,EAX                  ; Because of safety reasons
        MOV     CR3,EAX                  ; only erase the TLB  !
        JMP     FAR PTR FLUSH            ; Flush the Prefetch-Queue and
FLUSH   LABEL   FAR                      ; set the Attributes for CS newly
        MOV     AX,SEG MONDATA              ; Load DS newly, with that
        MOV     DS,AX                    ; of the Interrupt-Table so it's
        ASSUME  DS:MONDATA                  ; size can be
        LIDT    FWORD PTR [INTS_86]      ; set newly.
;        MOV     AX,SEG RES_STACK        ; The stack has to be recreated
;        MOV     SS,AX                   ; (in resident part
;        MOV     SP,OFFSET TOS           ; below 1 MB)
		JMP     FAR PTR BACK_TO_REALITY
RETURN_OF_THE_86 ENDP
;
; (Continuation of the return from Protected Mode)
; Generate a failure message (Number in DX)
;
BACK_TO_REALITY PROC FAR
	db 0eah,0,0,0ffh,0ffh		; jmp ffff:0
BACK_TO_REALITY endp

RESCODE ENDS


;
; The Data-area of the Monitor- & EMS-Program
;

MONDATA    SEGMENT PARA USE16
		ASSUME  CS:MONDATA
;(*-2-*)
		DB      10 DUP (0)
Kennung DB      'EMMXXXX0'                ; Identification of the EMM-Driver
sig2	DB		'EMMQXXX0'		; ID if NOEMS specified
        DB      'c''t_EMM'                ; Identification for ct_EMM

DUMMY_CALL:			          ; In case software (among them TURBO Pascal
        INT     67H		          ; Programs) gets the idea, by
        IRET				  ; calling CS:IP from the Interrupt-table
                                          ; of the EMM, to in fact call the
                                          ; EMM!


;******************************************************************************
; INT15 handler:
;    everything forwarded to old handler, except int15/87 = move_memory
;
;******************************************************************************
;(*-2-*)
	public NEW15
NEW15 PROC FAR
	CMP     AH,87H               	; is it a blockmove ?
	JZ      SHORT @@do_int1587 	 	;
	JMP     CS:DWORD PTR [OLDINT15] ; else forward to default handler
@@NO_MOVE:

;
; suggested by eric auer - and I like the idea (it's easy to implement)
;	it's easiest (for the moment), to change
;   the int15/87 into a magic, undocumented int67/87 function,
;   which is handled by the 'normal' int67 handler
;
; 	although not 100% efficient, as this will require 2 transitions
; 	DOS int15 --> V86 --> this code --> int67 --> done
;
;
;INT 15 - SYSTEM - COPY EXTENDED MEMORY
;
;        AH = 87h
;        CX = number of words to copy (max 8000h)
;        ES:SI -> global descriptor table (see #0403)
;Return: CF set on error
;        CF clear if successful
;        AH = status (see #0402)

@@do_int1587:
	MOV     AH,087h
	int 067h

	test ah,ah
	jz @@ok
	STC
@@ok:
	STI
	RET 2
NEW15 ENDP
;******************************************************************************

;MSG00   DB      CR,LF,'Left 8086-workingmode and returned to REAL-'
;        DB      'Mode.',CR,LF,'$'
;MSG01   DB      CR,LF,'$'
;MSG08   DB      'INT 08h: Doppelfehler (Gates - Wozniak 5-3 6-3 2-5 6-2)$'
;MSG09   DB      'INT 09h: x87 - Limit-ueberschreitung by Operand$'
;MSG0A   DB      'INT 0Ah: Invalid Task State Segment$'
;MSG0B   DB      'INT 0Bh: Segment not physically available - present$'
;MSG0C   DB      'INT 0Ch: Stack-Failure$'
;MSG0D   DB      'INT 0Dh: General Sicherheitsverletzung$'
;MSG0E   DB      'INT 0Eh: Page not physically available - present$'
;MSG0F   DB      'INT 0Fh: hoppla, gibt''s eigentlich nicht$'
; MSG99   DB      CR,LF,'A20 can't be closed - blocked!$'

;(#-3-#)
	public BaseAdr,BlockLen,PageReg,ChanFlags,Flags,TargetAdr,BuffStart,BuffLen
ALIGN 4
BaseAdr         DW      8 DUP (?)       ; Starting Block of the DMA-Channel
BlockLen        DW      8 DUP (?)       ; dto. Length of the Block
PageReg         DB      8 DUP (?)       ; Pageregister
ChanFlags       DW      8 DUP (?)       ; div. flags for Channels
Flags           DW      0               ; global flags

TargetAdr       DD      ?               ; Original adress for DMA
BuffStart       DD      ?               ; Beginning of the DMA-Buffer
BuffLen         DD      ?               ; Utilized part of the Buffer

PageLookUp      DB      0,2,3,1,0,0,0,0,0,6,7,5,0,0,0,0
PageXLat        DB      87H,83H,81H,82H,0,8BH,89H,8AH

OLD13           DD      ?               ; Address of old INT 13h
OLD40           DD      ?               ; Address of old INT 40h




;
; Control of INT 13h and also INT 40h because of DMA-support
;
NEW13 PROC FAR
        BTS     CS:[Flags],INT13Activ           ; The beginning.
        BTR     CS:[Flags],NeedBuffer           ; Rather disable always.
		PUSH    ECX
        MOV     ECX,8                           ; The Statusbits partly
@@Loop: MOV     CS:[ChanFlags+ECX*2-2],1100B	; = ModePrgrd+PagePrgrd
        LOOP    @@Loop				            ; initialise
	POP     ECX
        PUSHF					; Now call the old INT
        CALL    DWORD PTR CS:[OLD13]		; If an error occurs,
        PUSHF					            ; ... there is nothing !
	JC      @@Bye
        BTR     CS:[Flags],NeedBuffer		; Is it necessary to copy
        JNC     @@Bye				        ; back the buffer?
HLT13:  HLT                                 ; Hello, 32-Bit World !
@@Bye:  BTR     CS:[Flags],INT13Activ       ; Bye bye (Flags are being saved,
        POPF				                ; the BTR CY-flag erased !)
        RETF    2		                    ; delete flags on stack
NEW13 ENDP

NEW40 PROC FAR
        BTS     CS:[Flags],INT40Activ		; Here we go.
        BTR     CS:[Flags],NeedBuffer		; Rather disable always.
	PUSH    ECX
        MOV     ECX,8				; The statusbits partly
@@Loop: MOV     CS:[ChanFlags+ECX*2-2],1100B	; = ModePrgrd+PagePrgrd
        LOOP    @@Loop				; initialize.
		POP     ECX
        PUSHF					; Now call the old INT
        CALL    DWORD PTR CS:[OLD40]		; In case an error occurs,
        PUSHF					; ... nothing is !
		JC      @@Bye
        BTR     CS:[Flags],NeedBuffer		; Still necessary to copy
        JNC     @@Bye				; back the buffer ?
HLT40:  HLT                                     ; Hello, 32-Bit World !
@@Bye:  BTR     CS:[Flags],INT40Activ           ; Bye bye (Flags are being
        POPF					; saved, the BTR CY-Flag emptied !)
        RETF    2				; Back with the flags
NEW40 ENDP
;(#-3-#)

	ALIGN   4
;MSGTAB  DW      MSG08,MSG09,MSG0A,MSG0B,MSG0C,MSG0D,MSG0E,MSG0F

PSP		DW      ?            ; PSP of the program
OLDINT15        DD      ?            ; Address of the old INT 15h

INTS_86         DW      3FFH	     ; Size and state of the Interrupttable
                DD      0            ; (IDT) in REAL-Mode
IDT_PTR         DW      7FFH	     ; Size and state IDT in Pro
                DW      OFFSET IDT,0 ; (Will be adjusted later again !)
GDT_PTR         DW      GDT_LEN-1	 ; Size and state GDT in Pro
		DW      OFFSET GDT,0

;(*-3-*)
OLDINT67        DD      ?            ; Alter the EMM-Vector
;EXTMEM         DW      ?            ; Extended Memory in kBytes
public 	_MONITOR_ADDR
_MONITOR_ADDR   DD  100000H +EXT*1024   ; Beginning of the Monitor-Code

public _EMM_MEMORY_END              	; end of memory for EMM
_EMM_MEMORY_END dd 0

public _TOTAL_MEMORY		    ; highest physical address in machine
_TOTAL_MEMORY	dd      0

public PAGEDIR
PAGEDIR         DD      ?	    ; ^ up Page Directory (later CR3)

public FIRSTPAGE
FIRSTPAGE       DD      ?	    ; ^ up first available EMS-page

STATUSTABLE     DD      ?           ; ^ statustable for EMM Handles
EMSPAGETABLE    DD      ?	    ; ^ up Belegungstabelle der
_MAXPAGES       DW      ?	    ; EMS-pages Maximal available
_PAGESAVAIL      DW      ?	    ; EMS-pages currently available
_FRAME          DW      0D000H	    ; EMS-page Segmentaddress of the
FRAMEANCHOR     DD      ?	    ; EMS-"Frame" ^ up entry in
PHYSPAGETABLE   DW      4 DUP (-1)  ; Page Table up-to-date faded in
				    ; pages

TSS_Address		DD	0	; TSS address after moved to high memory
VCPI_Tracking	DD	0	; address of VCPI tracking control page
PageMapSave		DW	2 DUP (?)	; first two EMS physical page maps store
RegionSource	DD	0	; function 57h region source
RegionDest		DD	0	; function 57h region destination
RegionCount		DD	?	; function 57h region count
CR3_Save		DD	?	; temporary store of CR3 value not EMM386's
CX_Save			DW	0	; temporary store of cx value

; boolean flags
_NoVCPI			DB	0	; flags no VCPI services
_FlagNOEMS		DB	0	; flags no EMS services
_NoPageFrame	DB	0	; flags FRAME=NONE
_SB				DB	0	; flags SB (soundblaster drivers)
_AltBoot		DB	0	; flags AltBoot (don't check INT 9 for Ctrl-Alt-Del)
Xchg_Flag		DB	0	; EMS 4.0 func. 57h move/exchange memory region flag
VCPI_PM_call	DB	0	; flags call to VCPI via protected mode rather than INT 67h

				    ; Flag to enable/disable special
				    ; handling of INT67/44 (MAP_PAGE)
				    ; during init phase, abused to map UMB everywhere
	public _INIT_DONE
_INIT_DONE		db		0			; reset after initialization

_startup_verbose db 0		    ; more (debug) output in Init Phase


    public _FlagKILLAbove64M	
_FlagKILLAbove64M db 0          ; this driver supports > 64M memory, no need to kill



;(*-3-*)
;
; GDT - Global Descriptor Table. This table holds the descriptions
; of all  public Data-, Code-, LDT- and Task-Segments
;
		ALIGN   4
GDT     LABEL BYTE
  DQ            0                               ; NULL-Entry
  SELECTOR <OFFSET LDT>,LDT_LEN,82H,0           ; LDT-Descriptor
  SELECTOR <OFFSET TSS>,TSS_LEN,89H,0           ; TSS V86
  SELECTOR <OFFSET TMP_TSS>,TMP_TSS_LEN,89H,0   ; Temporary TSS
  SELECTOR 0,0FFFFH,9AH,0                       ; "Normal" Codesegment (64k)
  SELECTOR 0,0FFFFH,92H,0                       ; "Normal" Datasegment with
                                                ; REAL-Attributes
server_GDT_Universe:
  DW 0FFFFH,0                                   ; 4-GByte-Adress-space
  DB 0,92H,0C0H+0FH,0

; put V86 stack segment in GDT to help out debugger
  SELECTOR 0,V86_TOS,92H,0			 ; Stack-Segment V86 (16 Bit)

; NULL entries for debugger purposes
  DQ	0, 0, 0, 0, 0, 0, 0, 0
GDT_LEN EQU     $-GDT
;
; LDT - Local Descriptor Table. This table holds the Code-, Data-
; and Stack-Segment exclusiv(-ely) for the virtual Monitor (thus DPL = 0).
;
LDT     LABEL BYTE
  DQ            0                                ; NULL-Entry
server_GDT_Code:
  SELECTOR 0,V86_LEN,09AH,0			 ; Code-Segment V86  (16 Bit) use32
server_GDT_Data:
  SELECTOR		0,WHOLE_DATA_LEN,92H,0	 ; Data-Segment V86 (16 Bit)
;  SELECTOR 0,V86_TOS,92H,0			 ; Stack-Segment V86 (16 Bit)
LDT_LEN EQU     $-LDT
		PURGE   SELECTOR

public DATA_END
DATA_END        EQU     $			 ; End of resident part


;
; Now the Interrupttable (IDT) follow, these contain the "Gates" for
; Exceptions or Interrupts in Protected Mode. Beware: So that the processing can take
; place duly, the condition that DPL = 3 must be valid !

IDT_ENTRY_O MACRO SEQNR				;; Unfortunately this is the only way
        DW      OFFSET INT&SEQNR		;; the Symbolname INTxx is correctly
		ENDM				;; produced.

IDT_ENTRY MACRO FROM,TO				;; Interrupt Gates producer
		LOCAL   ENTRY
ENTRY   =       FROM
		REPT    TO-FROM+1
		IDT_ENTRY_O %(ENTRY)		;; Offset 15..0 of target
             DW      V86_CODE_SEL		;; Code-Segment-Selector of Target
		DB      0,0EEH                  ;; Interrupt Gate (DPL=3, 32 Bit)
		DW      0			;; Offset 31..16
ENTRY   =       ENTRY+1
		ENDM
		ENDM

IDT     LABEL BYTE
                IDT_ENTRY 00H,0FFH               ; Interrupt-Table
IDT_LEN EQU     $-IDT
		PURGE   IDT_ENTRY,IDT_ENTRY_O
;
; TSS - priry Task State Segment; is needed during the initialisation,
; to activate the 86-Monitor by Taskswitching.
; (Strictly not a single byte is needed, only the 386 is already happy
; with the sheer existence of it.)
; * When the first real TSS / task is activated, the 386 stores parts
; * of the current state to this "zeroth TSS" which can then be discarded.
;
TMP_TSS LABEL BYTE
                DW      0,0                  ; Back Link for verschachtelte Tasks
                DD      V86_TOS              ; Level 0 Stack
		DW      V86_STACK_SEL,0
		DD      0,0                  ; Level 1 Stack
		DD      0,0                  ; Level 2 Stack
                DD      0                    ; CR3 (for Paging)
		DW      OFFSET V86_START,0   ; EIP
		DD      0                    ; EFLAGS (IF = 0)
		DD      0,0,0,0              ; EAX/EBX/ECX/EDX
		DD      V86_TOS              ; ESP
		DD      0,0,0                ; EBP/ESI/EDI
		DW      V86_DATA_SEL,0       ; ES
		DW      V86_CODE_SEL,0       ; CS
		DW      V86_STACK_SEL,0	     ; SS
		DW      V86_DATA_SEL,0       ; DS
		DW      V86_DATA_SEL,0       ; FS
		DW      V86_DATA_SEL,0       ; GS
		DW      V86_LDT_SEL,0        ; LDT
		DW      0                    ; Debug-Bit 0
		DW      $+2-TMP_TSS          ; Offset I/O-Erlaubnis-Bitmap rel.
                                             ; TSS No I/O is permitted
TMP_TSS_LEN     EQU     $-TMP_TSS
;
; TSS - Task State Segment of the Monitor-Program (at the same time here ends
; the resident part of the program, the rest is shifted part-by-part in the
; range, to clean up MSDOS' memory space.)
;
DATA_LEN        EQU     OFFSET $
;
; This TSS is surely really needed!
;
TSS: ;     LABEL BYTE
        DW      0,0		     ; Back Link for interlocked Tasks
	DD      V86_TOS              ; Level 0 Stack
	DW      V86_STACK_SEL,0
	DD      0,0                  ; Level 1 Stack
	DD      0,0                  ; Level 2 Stack
	DD      0		     ; CR3 (for Paging)
	DW      OFFSET V86_START,0   ; EIP
	DD      0                    ; EFLAGS (IF = 0)
	DD      0,0,0,0              ; EAX/EBX/ECX/EDX
	DD      V86_TOS              ; ESP
	DD      0,0,0                ; EBP/ESI/EDI
	DW      V86_DATA_SEL,0       ; ES
	DW      V86_CODE_SEL,0       ; CS
	DW      V86_STACK_SEL,0      ; SS
	DW      V86_DATA_SEL,0       ; DS
	DW      V86_DATA_SEL,0       ; FS
	DW      V86_DATA_SEL,0       ; GS
	DW      V86_LDT_SEL,0	     ; LDT (not used!)
	DW      0                    ; Debug-Bit 0
	DW      $+2-TSS              ; Offset I/O-Erlaubnis-Bitmap rel.

;**********************************************************************

;(#-4-#)
Comment $
;(#-4a-#)
DB      10000H/8 DUP (0)        ; TSS all I/O-Addresses allowed, without 
DMA!
;(#-4a-#)
$
;*********************************************************************
;       Changed for I/O-control of the DMA-port
; The line "DB 10000H/8 DUP (0)" directly before this new change/adaptation
; has to be remarked or deleted!

		DB      11111111B,00011000B		; DMA-Controller #1
		; * trap ports 0..7, b, c ?
		DB      14 DUP (0)
		DB      10001110B,00001110B		; page register
		; * trap ports 81..83, 87, 89..8b ?
		DB      6 DUP (0)
		DB      11111111B,11111111B,01000000B	; DMA-Controller #2
		; * trap ports c0..cf, d6 ?
		DB      00000001B			; dto.
		; * trap port d8 ?
		DB      (10000H-0E0H)/8 DUP (0)
		; * allow all other ports
;(#-4-#)
                DB      0FFH                 ; wg. Readmechanism of the 80386
TSS_LEN EQU     $-TSS

MSGF			DB      ' Byte remaining resident, EMM386 returning to DOS',CR,LF,'$'
MSGFail			DB      ' something failed - driver aborted',CR,LF,'$'
msg_already_installed	DB	'EMM already installed',CR,LF,'$'

WHOLE_DATA_LEN  EQU     OFFSET $

MONDATA    ENDS
;
; Switch the processor into Protected-Mode and start the virtual working
; mode of the 80386. Start follows in REAL-Mode, and afterwards
; a Task-change is forced, through which the virtual 8086-Modus
; is started.
CODE    SEGMENT PARA USE16
	ASSUME  CS:CODE,DS:MONDATA

STORE MACRO ADDRESS
        MOV     EAX,EDI			    ;; Load the by <ADDRESS> described
        MOV     WORD PTR FS:[ADDRESS+2],AX  ;; Descriptor with the value
        SHR     EAX,16			    ;; from EDI.
	MOV     BYTE PTR FS:[ADDRESS+4],AL
	ENDM

REPMOVSB MACRO
        MOVZX   ECX,CX				; use 32 Bit-Adresses, so
        REP MOVS BYTE PTR [ESI],BYTE PTR [EDI]	; the entire Address-space
	BIG_NOP;
        ADD     EDI,3				; can be addressed.
        AND     DI,NOT 3			; Addresses in Longword
        ENDM					; round border, clear Bits 1 & 0

_pmessage macro line,col,c1,c2
	push ds
	push ax
	mov ax,UNIVERSE_SEL
	mov ds,ax
	mov byte ptr ds:[0b0000h+line*160+col*2+0],c1
	mov byte ptr ds:[0b0000h+line*160+col*2+1],070h
	mov byte ptr ds:[0b0000h+line*160+col*2+2],c2
	mov byte ptr ds:[0b0000h+line*160+col*2+3],070h
	inc byte ptr ds:[0b0000h+line*160+col*2+4]
	mov byte ptr ds:[0b0000h+line*160+col*2+5],070h
	pop ax
	pop ds
	endm

_pause macro line,col,c1,c2
	push ebx

	mov ebx, (line*80 + col) * 2
	call pause

	pop ebx
	endm



GO_PROTECTED PROC FAR
	CLI 	    			    ; do not disturb !
	CLD
	LIDT    FWORD PTR [IDT_PTR]	    ; Initialise pointers to IDT and GDT
	LGDT    FWORD PTR [GDT_PTR]
        MOV     BX,TMP_TSS_SEL		    ; Temporarily set temporary Task
        MOV     EAX,CR0			    ; Set the Protected-Mode-Enable-Bit in
        OR      EAX,1			    ; CR0 (?).
        MOV     CR0,EAX			    ; In Protected-Mode !
        JMP     SHORT $+2		    ; Prefetch-Queue flush
        LTR     BX			    ; Only select current TSS.
        MOV     AX,V86_LDT_SEL		    ; Also initialise LDT (only
	LLDT    AX			    ; now !)

	ASSUME  FS:MONDATA
        MOV     AX,UNIVERSE_SEL		    ; Addressing everything
	MOV     DS,AX
	MOV     ES,AX
	MOV     AX,V86_DATA_SEL		    ; GDT/LDT & Co.
	MOV     FS,AX

    MOV     EDI,FS:[_MONITOR_ADDR]      ; Start of Monitor-Code

; rearrange things so that the TSS gets a 4K boundary to satisfy
;  any possibility of crossing page border and causing problems with
;  rumored early CPUs that can fail in such circumstance
	mov	fs:[TSS_Address],edi	; save new location of TSS
	mov	esi,SEG MONDATA
	shl	esi,4
	mov	eax,OFFSET TSS
	add	esi,eax
	STORE   <OFFSET GDT+(V86_TSS_SEL AND 0F8H)>
	mov	cx,TSS_LEN
	REPMOVSB				; move the TSS to extended memory

        MOV     SI,SEG V86		    ; Calculate situation of the Monitor-
        MOVZX   ESI,SI			    ; Code in REAL-Mode
	SHL     ESI,4

;(#-6-#)
; Reserve the space for the DMA-Buffer
;
	MOV     FS:[BuffStart],EDI	    ; Store pointers.
        ADD     EDI,DMA_BUFF_SIZE*1024	    ; insert space for Buffer
;(#-6-#)

	STORE   <OFFSET LDT+(V86_CODE_SEL AND 0F8H)>
					     ; New situation of Code-Segments
        MOV     CX,V86_LEN		     ; Length of the code
	REPMOVSB

        MOV     SI,SEG MONDATA		     ; The Interrupt-Table dissapears
        MOVZX   ESI,SI			     ; also in Extended-range
	SHL     ESI,4
        MOV     EBP,ESI                      ; to keep it (for) later
	MOV     AX,OFFSET IDT
	MOVZX   EAX,AX
	ADD     ESI,EAX
        STORE   <IDT_PTR>		     ; Reset pointer to IDT
	MOV     CX,7FFH
	REPMOVSB
        LIDT    FWORD PTR FS:[IDT_PTR]	     ; load IDT-Base-register newly

comment $	; moved
        MOV     ESI,EBP                      ; Because the TSS hardly takes
        MOV     AX,OFFSET TSS	             ; litle space (over 8 kByte),it's
        MOVZX   EAX,AX			     ; being moved.
	ADD     ESI,EAX
	STORE   <OFFSET GDT+(V86_TSS_SEL AND 0F8H)>
	MOV     CX,TSS_LEN
	REPMOVSB
$

;(*-5-*)
; Now likewise initialize the variables of the Expanded MEMORY of manager (EMM).
; First comes the virtual store management 80386.

	ADD     EDI,4095                   ; Round to the next page border
	AND     EDI,NOT 4095


;        MOV     AX,FS:[__EXTMEM]           ; Determine for the order
;        ADD     AX,1024                    ; standing kBytes (inc. DOS = 1

	mov eax, FS:[_TOTAL_MEMORY]	    ; memory in byte
	shr eax, 10			    ; in kbyte

	SHR     eAX,2			    ; MByte) recalculate in pages (� 4 kBytes)
        SHR     eAX,10			    ; ... gives the number
        MOV     BX,1024                     ; of needed entries in the Page
	INC     AX                          ;  Directory
        SUB     BX,AX			    ; Set the rest later to 0

	MOV     ESI,111B                    ; R/W=1, U/S=1, P=1
        MOV     FS:[PAGEDIR],EDI	    ; Beginning of the Tabels (later in CR3)

	mov	edx,fs:[TSS_Address]
	mov	[edx+1ch],edi			; save (future) CR3 value to TSS

        MOV     EDX,EDI			    ; 1. Page Table start directly beyond
        ADD     EDX,4096                    ; the Page Directory 
@@FILL_PAGEDIR:
        MOV     [EDI],EDX	            ; physical address of the corresponding
	OR      BYTE PTR [EDI],111B	    ; page (Page Table) &
	ADD     EDI,4                       ;  Statusbits
	MOV     CX,1024			    ; In each case fill Page Table
@@FILL_PAGETABLE:
        MOV     [EDX],ESI		    ; Calculate situation of page in the physical
        ADD     ESI,4096                    ; Address-space and store in Page
        ADD     EDX,4                       ; Table
	LOOP    @@FILL_PAGETABLE
	DEC     AX
	JNZ     SHORT @@FILL_PAGEDIR
        MOVZX   ECX,BX			    ; Set rest of Page Directory to 0
	XOR     EAX,EAX                     ; ausnullen
	REP     STOS DWORD PTR [EDI]
        BIG_NOP				    ; For the old 386 (B3-Mask)
        MOV     EDI,EDX			    ; EDI allways points to the first
                                            ; free byte in Extended



;       MOVZX   EAX,FS:[__EXTMEM]	    ; Memory. Calculate the number of available pages
;       ADD     EAX,1024		    ; (� 4
;	sub	eax,EXT
;
;
;        SHL     EAX,10                     ; kBytes), of which the
;        SUB     EAX,EDI                    ; already used space is

	mov eax, FS:[_EMM_MEMORY_END]
	sub eax, EDI

	SHR     EAX,12			    ; subtracted.

; test for pathological case of no pages available here
	or	ax,ax
	je	compute_pages

        DEC     AX	; EMM requires itself a page. (4K-16K consumed depending on page rounding)

        SHR     AX,2			    ; Only recalculate in EMS-pages

; VCPI needs one 16K page to track its own allocations out of the EMS pool
	cmp	fs:[_NoVCPI],0	; see if VCPI allowed
	jne	check_control	; no

	cmp	ax,1			; see if sufficient pages for VCPI to give allocations
	jbe	check_control	; no
	dec	ax				; one page for VCPI
;	and	al,0feh			; two pages, if current pages are now odd to make them even
	mov	fs:[VCPI_Tracking],edi	; 16K control page for tracking VCPI allocations
	mov	ecx,4000h/4	; zero VCPI control page and advance edi
	xor	esi,esi
zero_control:
	mov	[edi],esi
	add	edi,4
	loop	zero_control

; since we're allowing more than 2K of EMS pages, we have to give EMM up to
;  two more 16K-sized control pages at the higher counts.  The two cut-off
;  values for each new control page are higher than 2048 EMS pages, but to
;  simplify things we'll always add two pages to the EMM requirements
;  when at or over the original 2048 value
;  (If >=32M and <??M, 16K-32K of extended memory wasted, big deal)
check_control:
	cmp	ax,2048
	jb	compute_pages
	sub	ax,2	; EMM requires two more fixed 16K-sized pages
compute_pages:

	MOV     FS:[_MAXPAGES],AX
	MOV     FS:[_PAGESAVAIL],AX
        MOV     FS:[STATUSTABLE],EDI	    ; Here starts the statustable of the
        MOV     AX,-1			    ; handles. Handle 0 is reserved
        STOS    WORD PTR [EDI]		    ; for the System, alle others are
        BIG_NOP				    ; prefix-adapted
        MOV     AX,-2			    ; -free
        MOV     ECX,256*4-1		    ; Entries still to fill for 255
	REP     STOS WORD PTR [EDI]	    ; Handles (REP STOSW, addr. size =
	BIG_NOP
        MOV     FS:[EMSPAGETABLE],EDI	    ; 32) Here the allocation of the
	MOV     ECX,2048                    ; EMS-pages starts

; alignment is now 2K, ensure that EMSPAGETABLE ends 4K aligned for
;  FIRSTPAGE (first page of EMS/VCPI storage)

; this is a little sloppy since the two extra page allocations kick in at 2046
;  (2048 - 2 allocated) pages instead of 2048, but they aren't used
;  until ~3.5K anyway, so it's safe and saves the small adjustment overhead
	cmp	fs:[_MAXPAGES],cx
	jb	got_ctrl_count
	mov	cx,MAX_EMS_PAGES_ALLOWED	; allow up to maximum number EMS pages
got_ctrl_count:

        MOV     AL,FREEPAGE_ID		    ; all currently free
	REP     STOS BYTE PTR [EDI]	    ; REP STOSB (addr. size = 32)
	BIG_NOP;

        MOV     FS:[FIRSTPAGE],EDI	    ; Mark the beginning of first EMS-page

	cmp	fs:[_NoVCPI],0
	jne	compute_anchor	; no VCPI

; VCPI should remain 4K-aligned from previous allocations
; allocate a single 16K page for VCPI
;  this allocation size can be internally increased as necessary without
;  fragmentation problems because the allocations can be discontinuous
	dec	fs:[_PAGESAVAIL]	; reduce available EMS pages
	mov	esi,fs:[STATUSTABLE]
	mov	WORD PTR [esi+8],-3		; mark handle 1 for VCPI (8 bytes/handle)
	mov	esi,fs:[EMSPAGETABLE]
	mov	BYTE PTR [esi],1		; mark first EMS page for VCPI (handle 1)

; In addition the situation of the entries in PAGE the Tables for EMS the window is to be
; determined. (Saves the need for doing later returning calculations)
;
compute_anchor:
        MOVZX   EAX,FS:[_FRAME]		    ; D000 Segmentaddress of the Frame
        SHL     EAX,4			    ; D0000 ... recalculate in absolute Adress
	MOV     ESI,FS:[PAGEDIR]
	SHR     EAX,10
	PUSH    EAX
	SHR     EAX,10			    ; Determine the pointers in the page table
	AND     EAX,111111111100B
	AND     ESI,NOT 111111111111B	    ; Throw statusbits out
	MOV     ESI,[ESI+EAX]		    ; read ^ of Page Table
	POP     EAX
        AND     EAX,111111111100B	    ; Same game again
	AND     ESI,NOT 111111111111B
	ADD     ESI,EAX
	MOV     FS:[FRAMEANCHOR],ESI
;(*-5-*)
; Small note about the following command: the Descriptor-Cache of the FS-
; Segmentregister contains after the execution again the old Segment-
; border! (Here that is insignificant, because no further
; accesses follows.)
	MOV     WORD PTR FS:[LDT+(V86_DATA_SEL AND 0F8H)],DATA_LEN
;
; Now finally all is prepared, so with a Task-switch the
; virtual 8086-Monitor can be started.
;
        JMP     DWORD PTR CS:[@@V86_ENTRY_ADDR]; force Task-change
@@V86_ENTRY_ADDR:
	DW      0,V86_TSS_SEL        ; "Address" Task State Segment
GO_PROTECTED ENDP

CODE    ENDS
;
; The actual Monitor for the virtual 8086-Modus. This range
; is paged out in the Extended Memory at 1 MByte.
;
V86     SEGMENT
	ASSUME  CS:V86,ES:NOTHING,FS:NOTHING,GS:NOTHING
;
; Within this routine the interrupts and exceptions handled as simply the
; interrupt call into the virtual 8086-Modus is reflected. Exceptions form
; only the error INTs 08h to 0Fh, which must be examined for it, if they are
; generated from hardware.
;
V86_MONITOR PROC NEAR
	PUSH    EAX
	PUSH    EBX
	PUSH    ECX

	movzx   esp,sp

					; ECX is a pointer into iterrupt table
					; or intno*4
	MOV     cX,[ESP+12]		; the return address = from where we were called
	SUB     cX,OFFSET INT_TABLE	; return address as unique identifier
	AND     ecX,0fffch		; for the corresponding IDT entry!
									; (ECX/4 = interrupt number)

; With the interrupts 08h - 0Fh is to be examined whether they were released by INT
; xx-command or hardware, or whether it concerns an exception interrupt .
; In addition it can also be, that the Monitor is being called recursively,
; because a HLT-command must be executed.
;
        CMP     ESP,V86_TOS-36H				; What did actually happen?!
	JZ      @@V86_ABORT				; an exception interrupt
        JB      @@PROTECTED			; Monitor is being interrupted

@@REENTRY:
        MOV     BX,UNIVERSE_SEL				; use 4-GByte-range for full access
        MOV     DS,BX					; to all Bytes.

	SUB     WORD PTR [ESP+14+12],6			; Create space for INT data

	MOVZX   EBX,WORD PTR [ESP+14+16]		; linear address of 86er-Stacks
	SHL     EBX,4					;
	movzx   eax,word ptr [ESP+14+12]		; use ONLY low portion SP,
	add 	ebx,eax					; as ESP may be undefined !


							; copy Interrupt frame down
	MOV     AX,[ESP+14]			        ; IP
	MOV     [EBX],AX
	MOV     AX,[ESP+14+4]				; CS
	MOV     [EBX+2],AX
	MOV     AX,[ESP+14+8]				; Flags
	MOV     [EBX+4],AX

;
; With the hardware interrupts 08h to 0Fh as well as 70h to 77h the interrupt flag is
; to be blocked

; reflecting an IRQ to whichever handler the V86 task "IDT" offers)...
;
	CMP     CX,08H*4                   ; range 08h to 0Fh ?
	JB      SHORT @@V86_CONT	   ; Otherwise, then further
	CMP     CX,0FH*4
	JBE     SHORT @@CLR_IF
	CMP     CX,70H*4                   ; Only within the range 70h to 77h
	JB      SHORT @@V86_CONT
	CMP     CX,77H*4
	JA      SHORT @@V86_CONT
@@CLR_IF:
	AND     WORD PTR [ESP+14+8],NOT 200H; Clear IF: stop Interrupts
				; clear IF if trigger was an hardware IRQ
				; * decided by int number, so reprogramming 8259
				; * would break this! Maybe an error code given to the
				; * handler could tell in more reliable way?
@@V86_CONT:
	AND     WORD PTR [ESP+14+8],NOT 100H; Clear TF: single step!
		    				; clear TF in any case

        MOV     BX,[ECX]			; Write new adress CS:IP from the 8086-
        MOV     [ESP+14],BX			; Tabel in the jumpback-address
        MOV     BX,[ECX+2]		        ; on the stack
	MOV     [ESP+18],BX

@@Clean:
        POP     ECX				; Clean everything properly
        POP     EBX
	POP     EAX

        INC     ESP				; Correct old call-adress
	INC     ESP

        IRETD		                        ; Return to virtual 86-Modus
                                                ; (only) via IRETD !
;
; Remove EFLAG, CS, IP, that are saved by the Interrupt again
; * This is called when an exception is generated by the monitor itself,
; * which we recognize by how much context is on stack (v86
;

@@PROTECTED:
        MOV     AX,[ESP+12]          ; Put new Interrupt-Nr (= return-
        MOV     [ESP+24],AX          ; address) in the correct Pos.
        MOV     EAX,[ESP+8]          ; move EAX, EBX, ECX
        MOV     [ESP+20],EAX         ; to above,
        MOV     EAX,[ESP+4]          ; so the stack for the virtual
        MOV     [ESP+16],EAX         ; Registers EFLAG, CS, IP can be cleared.
        MOV     EAX,[ESP]
	MOV     [ESP+12],EAX
	ADD     ESP,12               ; throw away EFLAG, CS, IP Protected Mode
	JMP     @@REENTRY            ; and go on.


@@V86_ABORT:
	CMP     CX,0DH*4             ; Privilegviolation ?
        JNZ     @@V86_ABORT_IT	     ; Everything else lies below it after all!

; see if SoundBlaster INT 3 forced to 1ah error code GPF
	CMP	DWORD PTR [ESP+14],1ah
	jne	notsb
	mov	ax,V86_DATA_SEL
;	push	ds
	mov	ds,ax
	cmp	_SB,0
;	pop	ds
	je	notsb					; SB option not turned on
	mov	ax,3*4+OFFSET INT_TABLE	; set configuration as if INT 3 occurred
	mov	[ESP+16],ax				; emulate call from INT 3 call address
	pop	ecx
	pop	ebx
	pop	eax
	add	sp,4					; discard excess GPF error code
	inc	DWORD PTR [ESP+2]		; increment EIP past INT 3 instruction
	jmp	V86_MONITOR
notsb:

        MOV     AX,UNIVERSE_SEL      ; Hello World, hello Universe !
	MOV     DS,AX

        MOVZX   EAX,WORD PTR [ESP+18+4]; examine wether a HLT-command the
	SHL     EAX,4                  ; has caused the Privilege fault
	ADD     EAX,[ESP+18]

					; EAX = linear CS:IP

;
; examination of the errorreleasing instruction
;
; check which command triggered the GPF: Special treatment for
; I/O commands (I/O only causes GPF for masked ports, as we only
; simulate the DMA chip) and HLT (if at magical locations, it is
; a wink by the V86 part of EMM386 to trigger DMA processing after
; int 13h / 40h). Non-magical HLT is handled by doing HLT for the
; user in the monitor. No other handling yet (e.g. privileged commands,
; LOCK and the like are just translated to an int 6, illegal opcode,
; which is then reflected to the V86 task!). The DMA chip has no 32bit
; registers, so only 8/16bit IN/OUT is trapped. String IN/OUT is not
; trapped either, but makes no sense with DMA chip anyway.
;
	MOV     BL,[EAX]                ; check opcode

	cmp	bl,0fh				; check if potentially mov <reg>,cr#
	je	@@ExtendedOp

	CMP     BL,0F4H                 ; HLT-
        JZ      @@Is_Hlt                ; command ?

	CMP     BL,0E4H                 ; IN/OUT ??
	JB      @@V86_ABORT_IT                   ;
	CMP     BL,0E7H                 ;
	JBE     @@DoIO_Im               ;
	CMP     BL,0ECH                 ;
	JB      @@V86_ABORT_IT                   ;
	CMP     BL,0EFH
	JBE     @@DoIO_DX

					; no handling for 32bit IN/OUT or other potential GPF causes

@@nix:
  JMP     @@V86_ABORT_IT          ; else complain!

@@ExtendedOp:
	cmp	BYTE PTR [eax+1],22h
	je	@@Check22
	cmp	BYTE PTR [eax+1],23h
	je	@@Check23
	cmp	BYTE PTR [eax+1],9
	je	@@wbinvd
	cmp	BYTE PTR [eax+1],32h
	je	@@rdmsr
	cmp	BYTE PTR [eax+1],20h
	jne	@@NIX		; not an opcode we emulate
	cmp	BYTE PTR [eax+2],0d8h	; 0f 20 d8 is mov eax,cr3 opcode
	jne	@@Check20Ext2
	mov	eax,cr3

@@extendedEAX:
	add	WORD PTR [esp+18],3		; jump over instruction

@@EAXnoadj:
	pop	ecx				; restore registers
	pop	ebx
	add	esp,4			; eat original eax value

@@Extret:
	add	esp,6			; eat return address and error code
	iretd

@@wbinvd:
	wbinvd				; 0f 09 is wbinvd opcode
	add	WORD PTR [esp+18],2		; jump over instruction
	pop	ecx				; restore registers
	pop	ebx
	pop	eax
	jmp	@@Extret

@@rdmsr:
	mov	ecx,[esp]		; get original ecx value
;	rdmsr				; 0f 32 is rdmsr opcode
	DB	0fh,32h			; no all assemblers know RDMSR, so force it in there
	add	WORD PTR [esp+18],2	; jump over instruction
	jmp	@@EAXnoadj

@@Check22:
	cmp	BYTE PTR [eax+2],0c0h	; 0f 22 c0 is mov cr0,eax opcode
	jne	@@NIX
	mov	eax,[esp+8]		; get original eax value
	mov	cr0,eax
	jmp	@@extendedEAX

@@Check23:
	cmp	BYTE PTR [eax+2],0f8h	; 0f 23 f8 is mov dr7,eax opcode
	jne	@@NIX
	mov	eax,[esp+8]		; get original eax value
	mov	dr7,eax
	jmp	@@extendedEAX

@@Check20Ext2:
	cmp	BYTE PTR [eax+2],0c0h	; 0f 20 c0 is mov eax,cr0 opcode
	jne	@@Check20Ext3
	mov	eax,cr0
	jmp	@@extendedEAX

@@Check20Ext3:
	cmp	BYTE PTR [eax+2],0c3h	; 0f 20 c3 is mov ebx,cr0 opcode
	jne	@@NIX
	mov	ebx,cr0
	add	WORD PTR [esp+18],3		; jump over instruction
	pop	ecx				; restore registers
	add	esp,4			; eat original ebx value
	pop	eax
	jmp	@@Extret

@@Is_Hlt:

        CMP     WORD PTR [ESP+18+4],SEG MONDATA ; Was a special HLT-command
        JNZ     @@Do_Hlt		; the cause for the


	MOV     AX,[ESP+18]             ; General Protection Fault ?
	CMP     AX,OFFSET HLT13		; * magical HLT in our disk / int 13 handler
        JZ      TRANSFER_BUFF		; copy buffer back
	CMP     AX,OFFSET HLT40		; * magical HLT in our disk / int 40 handler
	JZ      TRANSFER_BUFF
@@Do_Hlt:
;(#-7-#)

	INC     WORD PTR [ESP+18]   ; Jump over the HLT instruction
        POP     ECX                 ; restore Register
	POP     EBX
	POP     EAX
        ADD     ESP,6               ; throw away errorcode & returnaddress.
        STI                         ; give Interrupts free and then wait,
        HLT                         ; wait, wait........




;*************************************************************
; this driver isn't abortable (it holds UMBs,...)
;
; so we generate an INT 6 (invalid opcode) interrupt, and hope,
; that DOS aborts us
;
;*************************************************************
@@V86_ABORT_IT:                      ; Now conclusion is however final  !

						;>> by mov ax,[ffff]
		;>> by AX,0FFF1h		; otherwise provoke privilege errors
		;>> LMSW	 AX		; at the uninstall

						; ESP+22 = cs
						; ESP+18 = ip


        MOV     BX,UNIVERSE_SEL			; 4-GByte-range for to utilize full access
        MOV     DS,BX			        ; to all Bytes .
        MOVZX   EBX,WORD PTR [ESP+18+16]	; Calculate the absolute state
        SHL     EBX,4			        ; of the 86-Stack
	ADD     EBX,[ESP+18+12]			; (ESP 86er-Stack in addition)

	SUB     DWORD PTR [ESP+18+12],6		; room for IP,CS,FLAGS

        MOV     AX,[ESP+18]			; copy IP
	MOV     [EBX-6],AX
        MOV     AX,[ESP+18+4]			; dto. save CS
	MOV     [EBX-4],AX
        MOV     AX,[ESP+18+8]			; edit Flags
	MOV     [EBX-2],AX
;


                                    ; simulate invalid opcode interrupt
        MOV     BX,[ds:6*4]			; Write new address CS:IP of the 8086-
        MOV     [ESP+18],BX			; Table in the returnaddress
        MOV     BX,[ds:6*4+2]			; on the stack
	MOV     [ESP+18+4],BX

	AND     WORD PTR [ESP+18+8],NOT 100H	; clear TF (single step off)


        POP     ECX				; Clean everything again
	POP     EBX
	POP     EAX

        INC     ESP			        ; Correct old calling-address
	INC     ESP

	add     ESP,4   			; remove error word

        IRETD					; Return to virtual 86-Modus
                                                ; (only) via IRETD !

;***************************************


;        MOV     DX,CX				; Calculate number of the Interrupt
;        SHR     DX,2
;        JMP     DWORD PTR CS:[@@V86_ABORT_ADDR]
;@@V86_ABORT_ADDR:
;        DW      OFFSET RETURN_OF_THE_86,REAL_SEL

;(#-8-#)
;
; an IN/OUT-command now HAS to be emulated and the data has to be checked
;
@@DoIO_Im:
        REPCMD  PUSH,<EDX,ESI,EDI>		; save yourselves!
        INC     EAX				; turn into Opcode and read
        MOVZX   DX,BYTE PTR [EAX]	        ; the I/O-Adresse
	ADD     WORD PTR [ESP+18+12],2		; jump over instruction
@@WithDX:
	MOV     AX,V86_DATA_SEL
	MOV     DS,AX
        TEST    BL,00000010B			; Is it a IN-command ?
	JNZ     @@Im_Out			; Noe ... 'n oller OUT.
        TEST    BL,00000001B			; Width Word or Byte ?
	JNZ     @@Im_Word
        IN      AL,DX				; Read the date from Port
        MOV     [ESP+8+12],AL			; and return it.
@@Bye:  REPCMD  POP,<EDI,ESI,EDX,ECX,EBX,EAX>
	ADD     ESP,6
	IRETD

@@Im_Word:
        IN      AX,DX				; Same action like above but
        MOV     [ESP+8+12],AX			; now with/for 16 Bit
	JMP     @@Bye

@@Im_Out:
	MOV     AL,[ESP+8+12]			; Save opcode because of Byte/Word-Flag.
	REPCMD  PUSH,<BX,DX>			; First send Low Byte to the
	CALL    @@Do_IO				; port.
        REPCMD  POP,<DX,BX>			; (call back) Repeat Opcode and test,
        TEST    BL,00000001B			; if the Hi-Byte still can be send
        JZ      @@Bye
	INC     DX
	MOV     AL,[ESP+8+1+12]
	CALL    @@Do_IO
	JMP     @@Bye

@@Do_IO:
        CMP     DX,80H				; Has a Page-register
        JB      LIKE_DMA			; been adressed, or one
        CMP     DX,8FH				; of both DMA-
	JBE     LIKE_PAGE			; Controllers ?
	JMP     LIKE_DMA

@@DoIO_DX:
        REPCMD  PUSH,<EDX,ESI,EDI>	    	; save Register  .
	INC     WORD PTR [ESP+18+12]		; Jump over instruction
	JMP     @@WithDX

; Copy the DMA-buffercontents after termination of the DISK-I/O to the
; wanted target/location
; * This is triggered by an HLT at a magical location in our own int 13
; * and int 40 handlers. First the original int 13 / 40 is done, and
; * then things are copied to / from where the mapped memory -really- is.
; * Should only trigger if a matching DMA is pending. Tricky!
;
TRANSFER_BUFF PROC NEAR
        INC     WORD PTR [ESP+18]       ; Jump over HLT-command
	REPCMD  PUSH,<DS,ES,ESI,EDI>
	MOV     AX,V86_DATA_SEL
	MOV     DS,AX
	MOV     ESI,[BuffStart]         ; Get the basic data of the block which
	MOV     EDI,[TargetAdr]         ; can be shifted. Read currently
					; simulated DMA source / dest. / length

	MOV     ECX,[BuffLen]
	MOV     AX,UNIVERSE_SEL         ; The large liberty  ... every
	MOV     DS,AX                   ; wall fall simetimes!
	MOV     ES,AX
	CLD
	MOV     EAX,ECX
	AND     ECX,3
	REP     MOVS BYTE PTR [ESI],BYTE PTR [EDI]
	BIG_NOP
	MOV     ECX,EAX
	SHR     ECX,2
	REP     MOVS DWORD PTR [ESI], DWORD PTR [EDI]
	BIG_NOP
	REPCMD  POP,<EDI,ESI,ES,DS,ECX,EBX,EAX>
        ADD     ESP,6                   ; throw away return-address.
        IRETD                           ; back to virtual 8086-
TRANSFER_BUFF ENDP			; Mode.
;
; Access to a pageregister
;
; In: DX : Port-address; AL : Value
;
LIKE_PAGE PROC NEAR
        OUT     DX,AL				; release data
        MOV     BX,DX				; Look up the number that corresponds to the port
        MOVZX   EDI,BYTE PTR PageLookUp[BX-80H]
	MOV     PageReg[EDI],AL			; Buffer Bits 24-16
	BTR     ChanFlags[EDI*2],PagePrgrd	; Program page register
	JMP     READY?
LIKE_PAGE ENDP
;
; Supervise certain registers of the DMA (direct memory access) components
;
LIKE_DMA PROC NEAR
	OUT     DX,AL                   ; Pass on only once ...
        CMP     DX,0C0H                 ; Should the 2nd Controller
        JB      @@What?                 ; be programmed ?
        SUB     DX,0C0H-20H		; Then convert I/O-Adress in the range
	SHR     DX,1                    ; 10h - 1Fh
@@What?:
	CMP     DX,7                    ; Program addresses and/or length of the blocks
	JBE     @@BlockSet              ;
	CMP     DX,10H                  ; dto. 2nd DMA-Controller ?
	JB      @@Mode?
	CMP     DX,17H
	JBE     @@BlockSet
@@Mode?:
	CMP     DX,0BH                  ; "Mode Register" responded ?
	JZ      @@Mode8                 ; DMA-Controller #1 ?
	CMP     DX,1BH                  ; dto. #2 ?
	JZ      @@Mode16
	CMP     DX,0CH                  ; Soll das Hi/Lo-FlipFlop ge-
	JZ      @@Clear8                ; loescht werden ?
	CMP     DX,1CH
	JZ      @@Clear16
	JMP     @@Bye                   ; If everything fails ...
;
; Access to Startadress and/or Blocklength of a DMA-Channel
;
@@BlockSet:
        MOVZX   EDI,DX			; Compute the DmaChannel-number from the
	AND     DI,0110B                ; I/O-Adress (likewise already transformed)
	SHR     DI,1
        MOV     BX,HiLoFlag1            ; ... currently Controller #1
	CMP     DX,10H                  ; Something nevertheless the second CONTROLLER
	JB      @@Len?                  ; addressed ?
	ADD     DI,4                    ; Starting from that 4. Channel  (because of
	MOV     BX,HiLoFlag2            ; Private...)
@@Len?: TEST    DX,0001H                ; meant block length  ?
	JNZ     @@Length

        BTC     [Flags],BX			; toggle the Hi/Lo-Flag. Is
	JNC     @@AdrLo				; the Lo-Byte programmed ?
	MOV     BYTE PTR BaseAdr[EDI*2+1],AL	; Set the bits with high order
	BTR     ChanFlags[EDI*2],BasePrgrd	; 8-15 and clear Flag there
	JMP     READY?				; completely programmed.
@@AdrLo:
	MOV     BYTE PTR BaseAdr[EDI*2],AL	; Program Lo-Byte,
	BTS     ChanFlags[EDI*2],BasePrgrd	; so set Flag, while
	JMP     @@Bye				; still 8 Bits follow.

@@Length:
        BTC     [Flags],BX			; toggle Hi/Lo-Flag again.
	JNC     @@LenLo				; Otherwise nearly the same
	MOV     BYTE PTR BlockLen[EDI*2+1],AL   ; takes place here as before.
	BTR     ChanFlags[EDI*2],LenPrgrd	;
	JMP     READY?
@@LenLo:
        MOV     BYTE PTR BlockLen[EDI*2],AL	; programm Lo-Byte
	BTS     ChanFlags[EDI*2],LenPrgrd
	JMP     @@Bye

READY?: TEST    ChanFlags[EDI*2],1111B
						; = BasePrgrd+LenPrgrd+PagePrgrd+ModePrgrd
        JNZ     @@Bye			        ; All Registers initialised ?
	TEST    [Flags],11B	                ; INT13Active+INT40Active.
						; Is currently a Disk-
        JZ      @@Bye				; I/O-INT currently active ?
						; If not, (keep an eye wide shut and continue..)
						; Eyes too and through...
        CALL    CHK_CHANNEL			; Then check value
@@Bye:  RET
;
; Monitor "Mode Register" for the Transferdirection DMA <--> I/O
;
@@Mode8:
        MOVZX   EDI,AL				; Mask away the number of the DMA-Channel
	AND     DI,0011B
@@Mode8@16:
	SHL     AL,2				; Mask away the transfer direction from the
	AND     AL,00110000B			; remaining data
        AND     ChanFlags[EDI*2],NOT 00110000B	; and wrote it in the Statusdata
        OR      BYTE PTR ChanFlags[EDI*2],AL	; of the corresponding Channel
        BTR     ChanFlags[EDI*2],ModePrgrd
	JMP     READY?
@@Mode16:
	MOVZX   EDI,AL
	AND     DI,0011B			; Likewise out-mask the number of the DMA
						; (direct memory access) channel.
        ADD     DI,4				; It's about a 16bit channel
	JMP     @@Mode8@16
;
; Clear the Hi/Lo flip-flop of the appropriate DMA (direct memory access) CONTROLLER
;
@@Clear8:
        BTR     [Flags],HiLoFlag1		; It was like that already
	JMP     @@Bye
@@Clear16:
        BTR     [Flags],HiLoFlag2		; Number 2's turn..
	JMP     @@Bye
LIKE_DMA ENDP
;
; Check a memory-area, wether it lies in continuous physical memory
; in pages of 4K each
;
; In:  ESI: linear Startadress
;      ECX: Length of the range
; Out: CY-Flag: reset, ESI = physical adress
;               set, not constantly
;
CONTINUOUS? PROC NEAR
        PUSH    ES                      ; We need here immediately a bit
        MOV     AX,UNIVERSE_SEL         ; more space in Adress-space,
	MOV     ES,AX                   ; daher nun aufpusten...
	PUSH    ECX
        MOV     EAX,ESI                 ; Act like the Block begins,
        AND     EAX,4095                ; at a pageborder
        ADD     ECX,EAX                 ; for that, change Length
        PUSH    ESI                     ; to save later
	MOV     EAX,ESI
        SHR     ESI,20                  ; Determine the pointer of the corresponding
	AND     ESI,111111111100B	; entry in the page table.
	MOV     EBX,CR3
	ADD     ESI,EBX
	MOV     ESI,ES:[ESI]
	AND     ESI,NOT 4095
	SHR     EAX,10
	AND     EAX,111111111100B
	ADD     ESI,EAX
	MOV     EAX,ES:[ESI]		; Retreive state of the page in the phys. Adress
	AND     EAX,NOT 4095		; range
        PUSH    EAX                     ; save Bits 31-12
        SHR     ECX,12                  ; Calculate number of
        JCXZ    @@Ok                    ; overlapping pages. Zero is OK!
@@Loop: ADD     EAX,4096                ; Go one page and
        ADD     ESI,4                   ; one entry further
        MOV     EBX,ES:[ESI]
        AND     EBX,NOT 4095            ; no memory in between?
	CMP     EAX,EBX
        JNZ     @@Fail                  ; ...Below!
	LOOP    @@Loop
@@Ok:   REPCMD  POP,<EAX,ESI,ECX,ES>    ; The physical address results
	AND     ESI,4095                ; from the bits 31-12 of the page
	OR      ESI,EAX                 ; and the offset 11-0
	CLC                             ; ...its ok.
	RET
@@Fail: REPCMD  POP,<EAX,ESI,ECX,ES>    ; restore Register.
        STC			        ; ...not possible  !
	RET
CONTINUOUS? ENDP
;
; A DMA-Channel is completely with data about beginning and length
; supplied, so that a check can (and has to) take place.
;
; In: EDI: Channelnumber 0..7
;
CHK_CHANNEL PROC NEAR
        MOVZX   ECX,BlockLen[EDI*2]     ; Calculate length of the blocks
        INC     ECX                     ; which are transferred
        CMP     EDI,4                   ; In case we're dealing with a
        JB      @@Only8                 ; 16bit DMA-channel , words are transferred.
        ADD     ECX,ECX
        MOVZX   ESI,PageReg[EDI]        ; The base-adress always lies on a
        SHL     ESI,15                  ; Word-border and Bit 0 of the
        MOV     SI,BaseAdr[EDI*2]       ; pageregister is being ignored
	SHL     ESI,1
	JMP     @@Chk
@@Only8:
        MOVZX   ESI,PageReg[EDI]        ; For 8-Bit-DMA-Channels the
        SHL     ESI,16                  ; Adress-calculation is a bit
        MOV     SI,BaseAdr[EDI*2]       ; more easy...
@@Chk:
        BTR     [Flags],NeedBuffer      ; Initialise.
	MOV     [TargetAdr],ESI		; For savety save the data about the block
	MOV     [BuffLen],ECX
        CALL    CONTINUOUS?             ; Is the block occupying directly-(each other)following pages?
        JNC     @@Set

        MOV     AL,BYTE PTR ChanFlags[EDI*2]	; If a verify is wanted
        AND     AL,00110000B			; the buffer is completely unneeded
	JZ      @@Bye
	MOV     ESI,[BuffStart]			; if not, go over Buffer (and draw 4000 clocks...)
	BTS     [Flags],NeedBuffer
@@Set:
	MOV     DX,DI                   ; Calculate I/O-address from the
        ADD     DX,DX                   ; channelnumber
        CMP     EDI,4                   ; 8-bit or 16-bit channel ?
	JB      @@Set8

	BTR     [Flags],HiLoFlag2       ; DMA #2, HiLo-FlipFlop-Flag
        ADD     DX,DX                   ; The 2nd DMA-Controller
        ADD     DX,0C0H                 ; is located at 0C0h
	OUT     [0D8H],AL               ; Clear Hi/Lo-FlipFlop
	JMP     $+2                     ; ... leave some time.
	SHR     ESI,1                   ; The Baseadress is now
	MOV     AX,SI                   ; newly written in the Controller
	OUT     DX,AL                   ; Lo before Hi-Byte
	MOV     AL,AH                   ; in the usual Intel way.
	JMP     $+2
	OUT     DX,AL
	MOVZX   DX,PageXLat[DI]         ; Set I/O-Adress of the page-
	SHR     ESI,15                  ; registers.
	MOV     AX,SI                   ; Ship still the remaining 8 Bit of
	JMP     $+2                     ; the 24-Bit-Adress in the page register.
	OUT     DX,AL
	JMP     @@Cont
@@Set8:
	BTR     [Flags],HiLoFlag1       ; Clear DMA #1, HiLo-FlipFlop-Flag
	OUT     [0CH],AL                ; Hi/Lo-FlipFlop ...
	JMP     $+2                     ; ... and the remaining.
        MOV     AX,SI                   ; Program the base-address anew
        OUT     DX,AL                   ;
	MOV     AL,AH
	JMP     $+2
	OUT     DX,AL
        MOVZX   DX,PageXLat[DI]         ; Like above, but now that the
        SHR     ESI,16                  ; Adress-calculation appears to be a bit different
        MOV     AX,SI                   ; (and easier) with 8-Bit-DMA-
        JMP     $+2                     ; Channels.
	OUT     DX,AL
@@Cont:
; Now check, if the data (because of "Save") still needs to be copied first
; in the buffer

        BT      [Flags],NeedBuffer      ; Should a transfer happen via buffer at all?
        JNC     @@Bye
        MOV     AL,BYTE PTR ChanFlags[EDI*2] ; With a  Save (Memory
        AND     AL,00110000B            ; -> I/O) first initialize
        CMP     AL,00100000B            ; the buffer with the data
	JNZ     @@Bye

        MOV     ESI,[TargetAdr]         ; First copy the needed
        MOV     EDI,[BuffStart]         ; memoryblock in the
        MOV     ECX,[BuffLen]           ;  DMA-Buffer
	REPCMD  PUSH,<DS,ES>
	MOV     AX,UNIVERSE_SEL         ; ...a bit Universum
	MOV     DS,AX                   ; looks in now (Greetings also at
	MOV     ES,AX                   ; ' boundless ' !)
	CLD
	MOV     EAX,ECX
	AND     ECX,3
	REP     MOVS BYTE PTR [ESI],BYTE PTR [EDI]
	BIG_NOP
	MOV     ECX,EAX
	SHR     ECX,2
	REP     MOVS DWORD PTR [ESI], DWORD PTR [EDI]
	BIG_NOP
	REPCMD  POP,<ES,DS>
        BTR     [Flags],NeedBuffer      ; can go...
@@Bye:
	RET
CHK_CHANNEL ENDP
;(#-8-#)

;
; PAUSE :
;         wait a little bit, incrementing some screen memory -
;         so you see some little flashing before the program
;         looses control of itself :-)
;


pause proc near

	push ds
	push ax
	mov ax,UNIVERSE_SEL
	mov ds,ax

	add ebx, 0b0000h

	mov ax,0ffffh

@@loop:
	inc word ptr ds:[ebx]
	inc word ptr ds:[ebx+2]
	inc word ptr ds:[ebx+4]
	dec ax
	jne @@loop

	add ebx, 08000h

	mov ax,0ffffh

@@loop1:
	inc word ptr ds:[ebx]
	inc word ptr ds:[ebx+2]
	inc word ptr ds:[ebx+4]
	dec ax
	jne @@loop1


	pop ax
	pop ds
	ret

pause endp

V86_MONITOR     ENDP

; this handler is always present, there is no ALTBOOT option
;  there is ALTBOOT support now
;
; Special Ctrl-Alt-Del handler (should be off by default and only
; be enabled by the ALTBOOT option!). Translates Ctrl-Alt-Del into
; cold (out 64,fe) reboot to make sure that mapping / protected mode
; is not blocking the proper reboot process.
;
KBOARD PROC NEAR
        PUSH    EAX                     ; Everyone for himself! Evacuate or be wiped out!

;		; * should directly jump to @@CONT here unless ALTBOOT is enabled!

	mov	ax,V86_DATA_SEL
	mov	ds,ax
	cmp	_AltBoot,0
	jne	@@CONT

	MOV     AX,UNIVERSE_SEL		  ; flat 4 GB data segment
	MOV     DS,AX

	movzx   esp,sp
	movzx	eax,WORD PTR [esp+6+4]	; get return CS
	shl	eax,4			; convert segment to address
	add	eax,[esp+6]		; add in return EIP
	cmp	eax,0ffff2h		; could only have come from FFFF:2 address
	je	kb_portreset

kb_keycheck:
        IN      AL,[PORT_A]	          ; get key-scancode
        CMP     AL,53H                    ; DEL ?
	JNZ     SHORT @@CONT
        MOV     AL,DS:[@KB_FLAG]          ; Have the keys CTRL & ALT
        AND     AL,1100B                  ;  been pressed ?
        CMP     AL,1100B                  ; If not,  continue working
	JNZ     SHORT @@CONT


					; why don't restart if E0 ??
					; TE 01 jul 02
					; these 2 changes help toshiba notebooks reboot.

;		TEST    BYTE PTR DS:[@KB_FLAG_3],10B; 0E0h sent (special key)
;		JNZ     SHORT @@CONT			; ? then never restart !

;							; and a warm start isn't a good idea ...

		MOV     WORD PTR DS:[@RESET_FLAG],1234H; Otherwise one


kb_portreset:
;	mov     al,0feh			; reset, using the keyboard
;;	out	dx,al			; (pulse hardware reset line)
;	out	64h,al			; (pulse hardware reset line)


					; if that doesn't work,
					; do a more conventional
					; jmp ffff:0 from real mode


	JMP     DWORD PTR CS:[@@ABORT_ADDR]; not Warmstart and
@@ABORT_ADDR:                        ; back to REAL-Mode
	DW      OFFSET RETURN_OF_THE_86,REAL_SEL


@@CONT: POP     EAX
	JMP     V86_MONITOR		; JMP, not CALL, as the address
					; where the call comes from must
					; stay on stack for the handler.
KBOARD ENDP
;
; Entrypoint because of the task swap after the switch into
; protected mode to start the virtual 8086 -working
; Note: we're currently in a 16-bit segment!
;
V86_START PROC NEAR
	PUSH    0
	PUSH    0                    ; GS  The Stackframe fo the
	PUSH    0                    ;     switch to 8086-mode
	PUSH    0                    ; FS
	PUSH    0                    ;
	PUSH    SEG MONDATA             ; DS
	PUSH    0
	PUSH    0                    ; ES
	PUSH    0
	PUSH    SEG TMP_STACK        ; SS
	PUSH    0
	PUSH    OFFSET TMP_TOS       ; ESP
	PUSH    0002H                ; EFLAGS: VM, IOPL=3, IF
	PUSH    3200H
	PUSH    0
	PUSH    SEG _TEXT            ; CS
	PUSH    0
	PUSH    OFFSET KEEP          ; EIP
	CLTS                         ; TS-Flag Clear (Task Switch) absolutely
                                     ; thus the next
                                     ; x87-command without INT 7 is being executed

;(*-6-*)
        MOV     AX,V86_DATA_SEL	     ; Throw out still the "Anchor" for the
        MOV     FS,AX                ; virtual memory-administration needed
        MOV     EAX,FS:[PAGEDIR]     ; Tables
	MOV     CR3,EAX
        MOV     EAX,CR0              ; Now enable Paging
	OR      EAX,80000000H
	MOV     CR0,EAX
;(*-6-*)
        IRETD                        ; With this single command the 8086-workingmode
                                     ; is being started.
V86_START ENDP
;
; here starts the interrupt table of the virtual 8086 Monitor.
; now only these table addresses are validm the tables from 0:0 not anymore

INTENTRY_O MACRO SEQNR               ;; Unfortunaly the symbol name INTxx is only
INT&SEQNR:                           ;; correctly produced in this way.
		ENDM

INTENTRY MACRO VON,BIS               ;; Generate entrypoint  for Interrupts in the
                LOCAL   ENTRY        ;; indicated range (for
ENTRY   =       VON                  ;; Mathematicians: Interval)
                REPT    BIS-VON+1    ;;
		INTENTRY_O %(ENTRY)  ;; Call the virtual 86-Monitor with
		CALL    V86_MONITOR  ;; the return address as reference.
		NOP                  ;; Align (at 4 Bytes)
ENTRY   =       ENTRY+1
		ENDM
		ENDM

INTENTRYNR MACRO INTRNR,ADDRESS      ;; Purposefully call a routine
		INTENTRY_O %(INTRNR)
		ADDRESS
		NOP                  ;; Align
		ENDM

INT_TABLE:
		INTENTRY 0,8                 ; Redirect All Interrupts, up to the
		INTENTRYNR 09H,<CALL KBOARD> ; keyboard- Interrupt to the
				             ; Monitor

;********************************************************************
;(*-7-*)
comment $
;(*-7a-*)
	   INTENTRY 10,255  ; This line is faded out with EMM
;(*-7a-*)
$
; The line INTENTRY 10,255 directly above (*-7-*) needs to deleted!!!
;********************************************************************
		INTENTRY 10,66H
                INTENTRYNR 67H,<JMP  EMM_ENTRY>; EMM-Driver
		INTENTRY 68H,255
;(*-7-*)

		PURGE   INTENTRY,INTENTRY_O,INTENTRYNR

;(*-8-*)
;
; Here starts the Expanded Memory Manager (EMM) Version 4.0
;
; The definitions of the situation of the Segmentregister can of course be changed,
; when in Dispatcher EMM_ENTRY following registers are saved
;
V8086_ES        EQU     <ESP+34>          ; ES on the Level-0-Stack
V8086_DS        EQU     <ESP+38>          ; DS on the Level-0-Stack

MAX_HANDLES     EQU     255               ; There are only 255 handles to give away (lt.
                                          ; Documentation  LIM EMS 4.0)
                                                                 ;
FREEPAGE_ID     EQU     255               ; Owner Handle of a free page
EMM_ENTRY PROC NEAR
		ASSUME  FS:MONDATA
		PUSH    ESI               ; In any case save the endangered
		PUSH    EDI               ; registers
		PUSH    ECX
		CLD

                MOV     CX,UNIVERSE_SEL   ; address everything
		MOV     DS,CX
		MOV     ES,CX
		MOV     CX,V86_DATA_SEL
		MOV     FS,CX
		mov	fs:[VCPI_PM_call],0	; flag this is an INT 67h
		movzx	esp,sp

					  ;
					  ; hack: handle undocumented
					  ; int67/87 function = simulated int15/87
					  ;
		cmp     ah,087h
		jne	normal_emm_functions

		pop     ecx
		CALL    SIMULATE_INT1587
		jmp     @@BYECX


normal_emm_functions:

; EMS 4.0 functions may need CX value
		pop	ecx
		mov	fs:[CX_Save],cx
		push	ecx

		MOVZX   ECX,AH		    ; Set the adress of the wanted Routine.

		cmp	cl,0deh			; see if VCPI function
		jne	not_vcpi_api
		movzx	ecx,al

IF	VCPI_DEBUG	EQ	1
		cmp	al,077h
		jne	debug2
		call	VCPI_Debugging
		jmp	@@BYE
debug2:
ENDIF

		cmp	cl,0ch
		ja	emm_INV_CALL	; invalid VCPI call
		cmp	fs:[_NoVCPI],0	; check if VCPI turned off
		jne	emm_INV_CALL	; yes, return invalid code, flags VCPI not present for 0de00h
		shl	cx,1
		call	WORD PTR cs:[OFFSET VCPI_CALL_TABLE+ECX]
		jmp	@@BYE

not_vcpi_api:
		SUB     CL,40H		    ; If outside of the permitted range,
		JB      SHORT emm_INV_CALL    ; then report
                CMP     CL,1DH              ; failure/error
		JA      SHORT emm_INV_CALL

		cmp	fs:[_INIT_DONE],0	; see if still initializing
		je	@@makecall		; yes, don't turn off EMS functions yet

		cmp	fs:[_FlagNOEMS],0
		jne	@@limitedEMS
		cmp	fs:[_NoPageFrame],0
		je	@@makecall

; allow non-mapping EMS functions with NOEMS or no page frame
@@limitedEMS:
		cmp	cl,1
		je	@@noems_fail	; function 41h
		cmp	cl,3
		jbe	@@makecall		; function 40h,42h-43h
		cmp	cl,4
		je	@@noems_fail	; function 44h
		cmp	cl,6
		jbe	@@makecall		; function 45h-46h
		cmp	cl,0ah
		jbe	@@noems_fail	; function 47h-4ah
		cmp	cl,0dh
		jbe	@@makecall		; function 4bh-4dh
		cmp	cl,10h
		jbe	@@noems_fail	; function 4eh-50h
		cmp	cl,14h
		jbe	@@makecall		; function 51h-54h
		cmp	cl,17
		je	@@makecall		; function 57h
		cmp	cl,18h
		jbe	@@noems_fail	; function 55h-56h,58h
		cmp	cl,1ah
		jbe	@@makecall		; function 59h-5ah

@@noems_fail:
		mov	ah,91h			; feature not supported error code
		jmp	@@BYE

@@makecall:
		SHL     CX,1
		CALL    WORD PTR CS:[OFFSET CALL_TABLE+ECX]

@@BYE:  POP     ECX
@@BYECX:POP     EDI
		POP     ESI                  ; restore Register again
		cmp	fs:[VCPI_PM_call],0
		jne	PM_ret		; don't IRETD from protected mode call

		IRETD                        ; 32-Bit-Return !!!
emm_INV_CALL:
                MOV     AH,84H               ; "Invalid Functioncode in AH"
		JMP     SHORT @@BYE
EMM_ENTRY ENDP

; entry for EMM386 routines called from protected mode
PM_ENTRY	PROC
	push	eax
	mov	ax,ss
	lar	eax,eax
	test	eax,400000h
	jnz	stack32
	movzx	esp,sp
stack32:
	pop	eax

	cmp	ax,0de0ch		; see if switch from protected mode to V86 mode
	je	VCPI_PMtoV86	; yes, give it special handling
	pushfd
	push	ds			; have to save segments for p-mode entry
	push	es
	push	fs

	push	esi			; setup same as dispatch routine since we're jumping in the middle
	push	edi
	push	ecx
	cld
	
	mov	cx,cs
	add	cx,8			; UNIVERSE_SEL value
	mov	ds,cx
	mov	es,cx
	add	cx,8			; V86_DATA_SEL
	mov	fs,cx

	mov	fs:[VCPI_PM_call],1	; flag this is a PM call, not an INT 67h
	cmp	ax,0de01h		; don't allow 0de01h from protected mode
	je	emm_INV_CALL

	jmp	normal_emm_functions

PM_ret:
	pop	fs
	pop	es
	pop	ds
	popfd
	DB	66h				; make 32-bit retf
	retf
PM_ENTRY	ENDP

;************************************************************
; simulate INT15/87
;
;INT 15 - SYSTEM - COPY EXTENDED MEMORY (by RBIL)
;
;        AH = 87h
;        CX = number of words to copy (max 8000h)
;        ES:SI -> global descriptor table (see #0403)
;Return: CF set on error
;        CF clear if successful
;        AH = status
;
;Values for extended-memory copy status:
; 00h    source copied into destination
; 01h    parity error
; 02h    interrupt error
; 03h    address line 20 gating failed
; 80h    invalid command (PC,PCjr)
; 86h    unsupported function (XT,PS30)
;
;Format of global descriptor table:
;Offset  Size    Description     (Table 0403)
; 00h 16 BYTEs   zeros (used by BIOS)
; 10h    WORD    source segment length in bytes (2*CX-1 or greater)
; 12h  3 BYTEs   24-bit linear source address, low byte first
; 15h    BYTE    source segment access rights (93h)
; 16h    BYTE    more rights
; 17h    BYTE    8 bit  linear source adress, high
; 18h    WORD    destination segment length in bytes (2*CX-1 or greater)
; 1Ah  3 BYTEs   24-bit linear destination address, low byte first
; 1Dh    BYTE    destination segment access rights (93h)
; 1eh    byte    more rights
; 1fh    BYTE    8 bit  linear source adress, high
;************************************************************

SIMULATE_INT1587 proc near

;        ES:SI -> global descriptor table (see #0403)

	movzx	ecx,cx				; verify size

	jecxz	@@OK				; we are done

	MOVZX   edi,WORD PTR [V8086_ES]; make edi = linear address of command
	SHL     edi,4
	MOVZX   esi,si
	add     edi,esi

	shl	ecx,1				; verify, source and destination
						; descriptors are ok
	cmp	cx, word ptr [edi+10h]
	ja	@@invalid_command

	cmp	cx, word ptr [edi+18h]
	ja	@@invalid_command

	shr	ecx,1
						; we don't care about segment access rights


						; load the source/destination
						; adresses

; 12h  3 BYTEs   24-bit linear source address, low byte first
; 17h    BYTE    8 bit  linear source adress, high
; 1Ah  3 BYTEs   24-bit linear destination address, low byte first
; 1fh    BYTE    8 bit  linear source adress, high

	push edx				; must be protected


	mov dl,[edi+17h]			; get linear source address
	shl edx,8
	mov dl,[edi+14h]
	shl edx,16
	mov dx,[edi+12h]

	mov esi,edx

	mov dl,[edi+1fh]			; get destination source address
	shl edx,8
	mov dl,[edi+1ch]
	shl edx,16
	mov dx,[edi+1ah]

	mov edi,edx

	mov dx,es				; get es=ds
	push ds
	pop es

	cld

	shr ecx,1
	REP MOVS DWORD PTR [ESI],DWORD PTR [EDI];
	BIG_NOP;
	adc ecx,ecx
	REP MOVS WORD PTR [ESI],WORD PTR [EDI];
	BIG_NOP;

	mov es,dx

	pop edx

@@ok:
	mov   AH,0                    ; everything OK and finished
	RET

@@abort:
	mov   AH,1                    ; everything OK and finished
	RET


@@invalid_command:
	mov ah,80h
	ret

SIMULATE_INT1587 endp


CALL_TABLE DW OFFSET GET_STATUS
		   DW OFFSET GET_PAGE_FRAME_ADDRESS
		   DW OFFSET GET_UNALLOCATED_PAGE_COUNT
		   DW OFFSET ALLOCATE_PAGES
		   DW OFFSET MAP_HANDLE_PAGE
		   DW OFFSET DEALLOCATE_PAGES
		   DW OFFSET GET_VERSION
		   DW OFFSET SAVE_PAGES
		   DW OFFSET RESTORE_PAGES
		   DW OFFSET NOT_IMPL
		   DW OFFSET NOT_IMPL
		   DW OFFSET GET_OPEN_HANDLES_COUNT
		   DW OFFSET GET_NR_OF_ALLOCATED_PAGES
		   DW OFFSET GET_ALLOCATED_PAGES
		   DW OFFSET SET_GET_PAGE_MAP
		   DW OFFSET NOT_IMPL	; 4fh
		   DW OFFSET ems4_map_multi	; 50h
		   DW OFFSET ems4_realloc	; 51h
		   DW ems4_attribute	; 52h
		   DW ems4_handle_names	; 53h
		   DW ems4_get_handle_info	; 54h
		   DW OFFSET NOT_IMPL	; 55h
		   DW OFFSET NOT_IMPL	; 56h
		   DW ems4_memory_region	; 57h
		   DW ems4_get_mappable_info	; 58h
		   DW ems4_get_config	; 59h
		   DW ems4_allocate_pages	; 5ah
		   DW OFFSET NOT_IMPL	; 5bh
		   DW OFFSET NOT_IMPL	; 5ch
		   DW OFFSET NOT_IMPL	; 5dh


VCPI_CALL_TABLE DW OFFSET VCPI_Presence	; 0
		   DW OFFSET VCPI_GetInterface
		   DW OFFSET VCPI_GetMax	; 2
		   DW OFFSET VCPI_GetFree
		   DW OFFSET VCPI_Allocate4K	; 4
		   DW OFFSET VCPI_Free4K
		   DW OFFSET VCPI_GetAddress	; 6
		   DW OFFSET VCPI_GetCR0
		   DW OFFSET NOT_IMPL	; 8
		   DW OFFSET NOT_IMPL
		   DW OFFSET VCPI_GetMappings	; 0ah
		   DW OFFSET VCPI_SetMappings
		   DW OFFSET VCPI_V86toPM	; 0ch

;
; AH = 40h: return the actual state of the EMM-driver.
;
GET_STATUS PROC NEAR
        XOR     AH,AH                    ; Allways everything OK.
	RET
GET_STATUS ENDP
;
; AH = 41h: request the segment address of the EMS-window
;
GET_PAGE_FRAME_ADDRESS PROC NEAR
        XOR     AH,AH                    ; No error occurred
        MOV     BX,FS:[_FRAME]           ; Segment address of EMS-Window/Frame
	RET
GET_PAGE_FRAME_ADDRESS ENDP
;
; AH = 42h: Request number of ( also maximum) available EMS-pages
;
GET_UNALLOCATED_PAGE_COUNT PROC NEAR
	XOR     AH,AH
        MOV     BX,FS:[_PAGESAVAIL]	; Amount of currently available pages
        MOV     DX,FS:[_MAXPAGES]       ; Amount of maximum available pages
	cmp	fs:[_FlagNOEMS],0
	je	unalloc_ret
	or	bx,bx
	je	unalloc_ret
	mov	bx,1			; only show maximum of 1 EMS page if NOEMS set

unalloc_ret:
	RET
GET_UNALLOCATED_PAGE_COUNT ENDP
;
; AH = 43h: Reserve Memoryspace of the EMS-add-on-card (ahemm..extinct...)
;
ALLOCATE_PAGES PROC NEAR
	MOV     AH,89H			; "Request, to reserve null pages"
	AND     BX,BX
	JZ      SHORT @@BYE
        MOV     AH,87H                  ; "Not enough pages available"
	CMP     BX,FS:[_MAXPAGES]
	JA      SHORT @@BYE
        MOV     AH,88H                  ; "Not enough pages available anymore"
        CMP     BX,FS:[_PAGESAVAIL]
	JA      SHORT @@BYE

allocate_pages_plus_zero:
        MOV     ESI,FS:[STATUSTABLE]	; Now search for a free Handle in the table
        MOV     ECX,MAX_HANDLES		;
@@SEARCH:
        CMP     WORD PTR [ESI],-2       ; Is there one free ... ?
	JZ      SHORT @@FOUND
	ADD     ESI,8
	LOOP    @@SEARCH
        MOV     AH,85H                  ; "No more free Handles"
@@BYE:  RET

@@FOUND:
;	PUSH    BX
        MOV     WORD PTR [ESI],-3        ; mark Handle as occupied

; zero page allocations allowed, so test and bypass code if found
	or	bx,bx
	je	allocate_exit
	push	bx

        SUB     FS:[_PAGESAVAIL],BX	 ; Take pages from the pool
	MOV     DX,MAX_HANDLES	         ; Set in CX now the actual Handle-
        SUB     DX,CX			 ; number, so the page
        MOV     EDI,FS:[EMSPAGETABLE]	 ; can be marked in the
        MOVZX   ECX,FS:[_MAXPAGES]	 ; page-usage-table as used
	MOV     AL,FREEPAGE_ID
@@SEARCH_PAGES:
        REPNZ   SCAS BYTE PTR [EDI]	; After searching for a free page
	MOV     [EDI-1],DL		; Assign the handle
	DEC     BX			; Continue until all desired pages are occupied
	JNZ     SHORT @@SEARCH_PAGES
	POP     BX

allocate_exit:
	XOR     AH,AH
	RET
ALLOCATE_PAGES ENDP
;
; AH = 44h: mirror logical page in the EMS-window
;
MAP_HANDLE_PAGE PROC NEAR
        CMP     AL,4			; not" Only pages 0..3
        JAE     SHORT @@PAGE_TO_LARGE   ; are allowed!

	CALL    TEST_HANDLE		; test remaining Handle
	PUSH    BX			; save BX  (since it is changed)
	AND     BX,BX			; In case the log. page number
	JS      SHORT @@MAP		; negative is, don't search, there
	INC     BX			; fade out
	MOVZX   ECX,FS:[_MAXPAGES]	; the range to search
	PUSH    AX			; AL cannot be disturbed
	MOV     AL,DL			; The handle to search
	MOV     EDI,FS:[EMSPAGETABLE]	; Search the allocation table by the pages
@@LOOP: REPNZ   SCAS BYTE PTR [EDI]	; occupied by the handle
	JNZ     SHORT @@NIX		; Out and past...
	DEC     BX			; The logical page is not yet
	JNZ     SHORT @@LOOP		; reached, so further !
        MOV     BX,FS:[_MAXPAGES]       ; Only calculate the absolute
        SUB     BX,CX                   ; logical pagenumber for MAP_PAGE
	DEC     BX
        POP     AX			; BI "cleans the stack"
@@MAP:  CALL    MAP_PAGE
	POP     BX
	XOR     AH,AH
@@BYE:  RET
@@NIX:  POP     AX			; restore Register again
	POP     BX
        MOV     AH,8AH                  ; "logical page out of
        RET				; reserved area"

;*******************************************************************************
; here comes the funny part (by Tom)
;		during initialization phase, calling EMM_MAP_PAGE (0x44)
;		with pysical page (AL) > 3 is possible.
;		meaning:
;
;		AL = highest 8 bits of logical adress, AL=E4 --> address E4000
;
;		initialization phase is terminated with AL=9F
;*******************************************************************************

@@PAGE_TO_LARGE:
        MOV     AH,8BH                    ; "Indicated physical page does not exist
        cmp     FS:[_INIT_DONE],0         ; still in init phase ?
	jne     @@BYE

	cmp	al,09fh			; AL=9f finishes init phase
	jne	@@TomsFunnyMapPage

	mov	FS:[_INIT_DONE],1	; finish initialization
	mov	ah,0			; success
	jmp @@BYE

	; the fun part - map in page DX:BX at address AL

@@TomsFunnyMapPage:

        MOV     AH,8BH                    ; "Indicated physical page doesn't exist
	AND     BX,BX                     ; In case the log. page number
	JS      SHORT @@BYE               ; negative is, no search

					  ; code stolen above
			                  ; find the memory for handle/page


	CALL    TEST_HANDLE		  ; test handed over Handle
	PUSH    BX			  ; save BX (since it is changed)

; convert 4K-based logical page to 16K-based
	shr	bx,2

	INC     BX			  ; Fade out
        MOVZX   ECX,FS:[_MAXPAGES]        ; Area to search within
	PUSH    AX			  ; AL may not be disturbed
	MOV     AL,DL                     ; Handle to search for
	MOV     EDI,FS:[EMSPAGETABLE]	  ; Search the allocation table for the page
@@XLOOP: REPNZ   SCAS BYTE PTR [EDI]	  ; corresponding to the handle
        JNZ     SHORT @@NIX		  ; Over and out...
        DEC     BX			  ; The logical page hasn't been
        JNZ     SHORT @@XLOOP		  ; reached yet, so go on !
        MOV     BX,FS:[_MAXPAGES]         ; Now calculate theabsolute logical
        SUB     BX,CX                     ; pagenumber for MAP_PAGE
	DEC     BX
        POP     AX	                  ; BI "cleans the stack"

;****
;**** stolen from MAP_PAGE
;**** with insertions from frameanchor calculation
;****
					; calculation of 'frame anchor'

		push	ax		; save segment frame
        MOVZX   EAX,AL                  ;  00E4 Segmentadresse of the Frame (Fensters)
        shl     EAX,8                   ; usual format,

        SHL     EAX,4                   ; D0000 ... calculate into absolute Adress
	MOV     ESI,FS:[PAGEDIR]
	SHR     EAX,10
	PUSH    EAX
	SHR     EAX,10			; Set pointer in the Page Directory
	AND     EAX,111111111100B
	AND     ESI,NOT 111111111111B	; throw out Statusbits
	MOV     ESI,[ESI+EAX]		; ^ read from Page Table
	POP     EAX
        AND     EAX,111111111100B       ; Same game all over again
	AND     ESI,NOT 111111111111B
	ADD     ESI,EAX

	; MOV     FS:[FRAMEANCHOR],ESI   ; esi = 'frame anchor'


        MOVZX   EDI,BX                  ; Now calculate, from the pagenumber
        SHL     EDI,14			; (absolute) the situation of the EMS-page
        ADD     EDI,FS:[FIRSTPAGE]      ; in Extended Memory .
        ADD     DI,111B                 ; Statusbits: R/W=1,U/S=1,P=1

;        MOV     CX,4                    ; 1 EMS entspr. 4 (virtual) pages
					; <VDS> support (haha - october 2002)
					; we return the start of physical memory
					; through dx:bx
					;
	pop	ax			; restore segment frame to ax
	POP     BX
	mov	cl,bl
	and	cl,3		; get 4K multiplier offset into 16K page
	movzx	ecx,cl
	shl	ecx,12		; convert multiplier offset to true 4K offset
	add	edi,ecx

; if segment frame value is 0ffh, then we know we're shadowing the ROM into RAM
;  to catch jumps to FFFF:0, so copy ROM image of block to RAM
	cmp	al,0ffh
	jne	noshadow
	pushf
	cli				; no interrupts while BIOS goes away
	push	esi
	push	edi
	and	di,0f000h	; strip off status bits of physical address, enforce 4K alignment
	push	edi
	movzx	esi,al
	shl	esi,12		; convert segment frame to absolute address
	mov	cx,1000h/4	; map 4K block in dwords
shadowloop:
	mov	eax,[esi]
	mov	[edi],eax
	add	edi,4
	add	esi,4
	dec	cx
	jne	shadowloop
	pop	edi
	add	edi,0ff0h
	mov	WORD PTR [edi],09cdh	; force INT 9 (to KBOARD) at FFFF:0
	pop	edi
	pop	esi
	popf

noshadow:
	push	edi

	mov	bx,di
	shr	edi,16
	mov	dx,di

	pop	edi
					; </VDS>


;	MOV     CX,4                    ; 1 EMS entspr. 4 (virtual) pages
;	MOVZX   ECX,CX
@@X2LOOP: MOV     [ESI],EDI             ; put in the new physical address of the
;        ADD     ESI,4                   ; Framepage
;       ADD     EDI,4096                ; Next 4K-page
;	LOOP    @@X2LOOP

        MOV     ESI,FS:[PAGEDIR]        ; To avoid failure through the TLB,
        MOV     CR3,ESI                 ; Load the TLB

	XOR     AH,AH
	RET

;*******************************************************************************
; end of fun :-)
;*******************************************************************************


MAP_HANDLE_PAGE ENDP



;
; AH = 45h: Release reserved memoryspace again
;
DEALLOCATE_PAGES PROC NEAR
        CALL    TEST_HANDLE		; First...
        MOV     AH,86H                  ; "A saved state still
        CMP     WORD PTR [ESI],-3       ; exists" ?
	JNZ     SHORT @@BYE
	PUSH    AX
        MOVZX   ECX,FS:[_MAXPAGES]	; All pages in the Belegungs-table
        MOV     AL,DL                   ; have to be marked again as free (= 0)
        MOV     EDI,FS:[EMSPAGETABLE]   ;
@@LOOP: REPNZ   SCAS BYTE PTR [EDI]     ; after searching pages with Handlenumber,
        JNZ     SHORT @@OK              ;  Everything has been done - ,Alles abgearbeitet ?
        MOV     BYTE PTR [EDI-1],FREEPAGE_ID; Mark page as free
	INC     FS:[_PAGESAVAIL]
	JMP     SHORT @@LOOP
@@OK:   MOV     WORD PTR [ESI],-2	; release Handle
	POP     AX
        XOR     AH,AH                   ; Function executed duly
@@BYE:  RET
DEALLOCATE_PAGES ENDP
;
; AH = 46h: determine Version-number of EMM
;
GET_VERSION PROC NEAR
;	MOV     AX,0032H                ; Currently version 3.2
	MOV     AX,0040H                ; Currently version 4.0
	RET
GET_VERSION ENDP
;
; AH = 47h: Save number of the fit-in page in EMS-window
SAVE_PAGES PROC NEAR
	CALL    TEST_HANDLE
        MOV     AH,8DH                 ; "State for Handle already
        CMP     WORD PTR [ESI],-3      ;     saved"
	JNZ     SHORT @@BYE
SAVE_TO_ESI:                           ; Re-entry point from functions  4Exxh
	PUSH    AX                     ; so that AL is saved
	MOV     AX,FS:[PHYSPAGETABLE]  ; the current logical page
	MOV     [ESI],AX               ; place within the action status range
	MOV     AX,FS:[PHYSPAGETABLE+2]
	MOV     [ESI+2],AX
	MOV     AX,FS:[PHYSPAGETABLE+4]
	MOV     [ESI+4],AX
	MOV     AX,FS:[PHYSPAGETABLE+6]
	MOV     [ESI+6],AX
	POP     AX
        XOR     AH,AH                    ; report 'everything OK'
@@BYE:  RET
SAVE_PAGES ENDP
;
; AH = 48h: Restore saved state of the EMS-window
;
RESTORE_PAGES PROC NEAR
	CALL    TEST_HANDLE
        MOV     AH,8EH                    ; "A saved stated does
        CMP     WORD PTR [ESI],-3         ; not exist"
	JZ      SHORT @@BYE
	CALL    RESTORE_FROM_ESI          ; Today ' times indirectly
	MOV     WORD PTR [ESI],-3         ; Nothing stored for Handle
        XOR     AH,AH                     ; report 'everything OK'
@@BYE:  RET

RESTORE_FROM_ESI:                         ; Re-entry for functions 4Exxh
        PUSH    AX		          ; save everything! Data- and System-
        PUSH    BX		          ; registers first!
        XOR     AL,AL                     ; fade in page 0 again
	MOV     BX,[ESI]
    	PUSH    ESI
	CALL    MAP_PAGE
	POP     ESI
	INC     AL			   ; Fade in page 1
	MOV     BX,[ESI+2]
	PUSH    ESI
	CALL    MAP_PAGE
	POP     ESI
	INC     AL			    ; page 2
	MOV     BX,[ESI+4]
	PUSH    ESI
	CALL    MAP_PAGE
	POP     ESI
	INC     AL			    ; page 3
	MOV     BX,[ESI+6]
	PUSH    ESI
	CALL    MAP_PAGE
	POP     ESI
	POP     BX
	POP     AX
        XOR     AH,AH                    ; report OK (because
        RET                              ;  of functions $4E01/$4E02)
RESTORE_PAGES ENDP
;
; report the failure so that we can maybe support it in the future
NOT_IMPL PROC NEAR

IF	UNIMPLEMENTED_EMS_DEBUG	EQ	1
	push	ax
	push	bx
	push	cx
	push	dx
	push	edi

	mov	bx,ax
	mov	edi,0b8000h
	mov	al,bh
	shr	al,4
	call	ni_post
	mov	al,bh
	and	al,0fh
	call	ni_post
	mov	al,bl
	shr	al,4
	call	ni_post
	mov	al,bl
	and	al,0fh
	call	ni_post

	pop	edi
	pop	dx
	pop	cx
	pop	bx
	pop	ax
ENDIF

        MOV     AH,84H                    ; "Invalid function code"
	RET

IF	UNIMPLEMENTED_EMS_DEBUG	EQ	1
ni_post:
	cmp	al,9
	jbe	ni_set
	add	al,7
ni_set:
	add	al,30h
	mov	ds:[edi],al
	add	di,2
	ret
ENDIF

NOT_IMPL ENDP
;
; AH = 4Bh: Number of open Handles
;
GET_OPEN_HANDLES_COUNT PROC NEAR
        MOV     ESI,FS:[STATUSTABLE] ; Search Handle-status-table for
        MOV     CX,MAX_HANDLES           ; assigned/given handles
	XOR     BX,BX
@@LOOP: CMP     WORD PTR [ESI],-2        ; Free ?
	JZ      SHORT @@CLOSED
	INC     BX
@@CLOSED:
        ADD     ESI,8                    ; Next entry.
	LOOP    @@LOOP
	XOR     AH,AH
	RET
GET_OPEN_HANDLES_COUNT ENDP
;
; AH = 4Ch: Determine number of reserved pages for a Handle
;
GET_NR_OF_ALLOCATED_PAGES PROC NEAR
	CALL    TEST_HANDLE
	PUSH    AX
	MOV     AL,DL                    ; After this handle search through the complete
	MOVZX   ECX,FS:[_MAXPAGES]	 ; page-allocation-table
	MOV     EDI,FS:[EMSPAGETABLE]
	XOR     BX,BX
@@LOOP: REPNZ   SCAS BYTE PTR [EDI]	 ; Search ...
        JNZ     SHORT @@OK		 ; No more found, so done
        INC     BX			 ; one page more
	JMP     SHORT @@LOOP
@@OK:   POP     AX
	XOR     AH,AH                    ; Ok.
	RET
GET_NR_OF_ALLOCATED_PAGES ENDP
;
; AH = 4Dh: determine Number of reserved pages for all Handles
;
GET_ALLOCATED_PAGES PROC NEAR
	MOVZX   ESI,WORD PTR [V8086_ES]	    ; ES from the Level-0-Stack
	SHL     ESI,4			    ; ES:DI ^ from the storage area
	MOVZX   EDI,DI
	ADD     ESI,EDI
	PUSH    AX
	PUSH    DX
	MOV     EDI,FS:[STATUSTABLE]
        XOR     AX,AX                    ; actual/current Handle-Number
        XOR     BX,BX                    ; sofar no Handle open
@@NEXT_HANDLE:
	CMP     WORD PTR [EDI],-2        ; Assign handle at all ? If
	JZ      SHORT @@NEXT		 ; not, then jump over
        INC     BX                       ; One more Handle is open...
        MOV     [ESI],AX                 ; Place handle
	INC     ESI
	INC     ESI
	PUSH    EDI
        MOV     EDI,FS:[EMSPAGETABLE]    ; Determine amount of reserved pages
        XOR     DX,DX                    ; for the handle
	MOVZX   ECX,FS:[_MAXPAGES]
@@LOOP: REPNZ   SCAS BYTE PTR [EDI]	 ; Search through Page-Allocation-Table
        JNZ     SHORT @@NOPE             ; No more found
	INC     DX
	JMP     SHORT @@LOOP
@@NOPE: MOV     [ESI],DX                 ; Set the number of determined pages
	INC     ESI
	INC     ESI
	POP     EDI
@@NEXT: ADD     EDI,8                    ; next Handle, please !
	INC     AX
	CMP     AX,MAX_HANDLES           ; All Handles processed ?
	JB      SHORT @@NEXT_HANDLE
	POP     DX
	POP     AX
	XOR     AH,AH                    ; Everything ok.
	RET
GET_ALLOCATED_PAGES ENDP
;
; AH = 4Eh: Get & Set Map
;
CHKSUM  MACRO   REG
	MOV     AX,[REG+2]           ; Calculate checksum
	ADD     AX,[REG+4]
	ADD     AX,[REG+6]
	ADD     AX,[REG+8]
	ENDM

SET_GET_PAGE_MAP PROC NEAR
        CMP     AL,3                    ; Subfunction 0 to 3 ?
	JA      SHORT @@NIX_IS
        JZ      SHORT @@SUBF_3          ; Size of field
	DEC     AL
	JZ      SHORT @@SUBF_1          ; Set Page Map
; Subf. 2: Get & Set Page Map
; Subf. 0: Get Page Map - save Hardwarestatus
@@SUBF_0:
	MOVZX   ESI,WORD PTR [V8086_ES] ; ES:DI ^ convert from statusfield in
	SHL     ESI,4                   ; usual REAL-Mode-Format
	MOVZX   EDI,DI
	ADD     ESI,EDI
        PUSH    AX			; save Subfunctioncode
        ADD     ESI,2                   ; Currently skip checsum
	CALL    SAVE_TO_ESI
	SUB     ESI,2
	CHKSUM  ESI                     ; Calculate checksum and ...
	MOV     [ESI],AX                ; ... store
        POP     AX                      ; restore and examen subfunctioncode
        CMP     AL,2                    ; if subfuction 2
        JZ      SHORT @@SUBF_1          ; is wanted , since then also
	XOR     AH,AH                   ; Subf. 1 still needs be done.
        RET                             ; Everything OK.

; Subf. 1: Set Page Map - restore Hardwarestatus
@@SUBF_1:
	MOVZX   EDI,WORD PTR [V8086_DS]; DS:SI ^ convert from statusfield in
	SHL     EDI,4                    ; usual REAL-Mode-Format
	MOVZX   ESI,SI
	ADD     ESI,EDI
	CHKSUM  ESI                      ; Calculate checksum and check it
	CMP     [ESI],AX
	JNZ     SHORT @@CHKERR
	ADD     ESI,2                    ; Jump over checksum
	JMP     RESTORE_FROM_ESI

; Checksum is incorrect !
@@CHKERR:
	MOV     AH,0A3H                  ; data is destroyed !
	RET

; Subf. 3: Size of the field
@@SUBF_3:
	MOV     AL,4*2+2                 ; 4 entries � 2 Byte + 2 Bytes
	XOR     AH,AH                    ; ChkSum
	RET			         ; That was it then.

bad_subfunc:
@@NIX_IS:
        MOV     AH,8FH                   ; Invalid subfunctioncode !
	RET
SET_GET_PAGE_MAP ENDP

;
; Paste a logical page into EMS-frame.
; AL = physical page 0 - 3, BX = logical page (absolute) or -1
;
MAP_PAGE PROC NEAR
	MOVZX   ESI,AL
	MOV     FS:[PHYSPAGETABLE+ESI*2],BX ; Place faded in page
	SHL     ESI,4			    ; Store the pointe of the entry
	ADD     ESI,FS:[FRAMEANCHOR]	    ; in the page table
	AND     BX,BX			    ; log. page < 0, then fade out
	JS      SHORT @@UNMAP
	MOVZX   EDI,BX			    ; Calculate now the (absolute) pagenumber
	SHL     EDI,14			    ; from the situation of the EMS-page in Extended
	ADD     EDI,FS:[FIRSTPAGE]	    ; Memory
@@SET:  ADD     DI,111B			    ; Statusbits: R/W=1,U/S=1,P=1
        MOV     CX,4			    ; 1 EMS entspr. 4 (virtual) pages
	MOVZX   ECX,CX
@@LOOP: MOV     [ESI],EDI                  ; Register the new physical Address of
	ADD     ESI,4                      ; window
        ADD     EDI,4096                   ; Process next 4K-page
	LOOP    @@LOOP
        MOV     ESI,FS:[PAGEDIR]	   ; To avoid error by the TLB,
        MOV     CR3,ESI                    ; , empty the TLB by loading of
        RET                                ; CR3
@@UNMAP:
        MOV     ECX,ESI                    ; save ESI!
        MOVZX   EDI,FS:[_FRAME]            ; During fade out applies "logical =
        SHL     EDI,4			   ; physical address"
	SHL     ESI,10
	ADD     EDI,ESI
	MOV     ESI,ECX
	JMP     SHORT @@SET
MAP_PAGE ENDP

;
; AH = 50h: EMS 4.0 map multiple pages
;  remember we must explicitly load cx value from its saved spot in
;  fs:[CX_Save] since EMM API dispatch code uses cx during the dispatch
;
ems4_map_multi PROC NEAR
	cmp	al,1	; only subfunction 0 supported
	ja	bad_subfunc	; this is an invalid subfunction
	je	NOT_IMPL

; perform handle check here so that stack return address isn't blown
;  on invalid handle MAP_HANDLE_PAGE call which directly manipulates it
	movzx	edi,si		; save critical entry register value
	call	TEST_HANDLE

	movzx	esi,WORD PTR [V8086_DS]	; DS from the Level-0-Stack
	shl	esi,4
	add	esi,edi	; esi -> map address buffer
	mov	cx,fs:[CX_Save]	; load EMM entry CX value

	push	bx

multi_loop:
	push	cx
	mov	bx,[esi]
	mov	ax,[esi+2]
	add	esi,4
	push	esi
	call	MAP_HANDLE_PAGE
	pop	esi
	pop	cx
	test	ah,ah
	jne	multi_out	; error occurred
	loop	multi_loop
	xor	ah,ah	; no error return

multi_out:
	pop	bx
	ret
ems4_map_multi ENDP

;
; AH = 51h: EMS 4.0 rellocate pages for handle
;
ems4_realloc PROC NEAR
	call	TEST_HANDLE
	push	bx		; save new pages
	call	GET_NR_OF_ALLOCATED_PAGES	; get current page allocation
	mov	di,bx		; save original page count
	mov	cx,bx
	add	cx,FS:[_PAGESAVAIL]	; get current pages for handle + available
	pop	bx			; restore new page request amount
	cmp	bx,cx
	ja	toomany

	movzx	ecx,FS:[_MAXPAGES]
	push	bx
	cmp	bx,di		; check new page count against original
	jb	shrinkalloc
	je	realloc_success	; no change needed

; growing the allocation of pages
	sub	bx,di		; get count of new pages needed
	mov	edi,FS:[EMSPAGETABLE]
	mov	al,FREEPAGE_ID
growpages:
	repnz	scas BYTE PTR [edi]
	mov	[edi-1],dl
	dec	FS:[_PAGESAVAIL]
	dec	bx
	jnz	growpages
	jmp	realloc_success

; trim off the top pages in case something stupid depends on page order
shrinkalloc:
	xchg	di,bx
	sub	bx,di		; get count of pages to reduce
	mov	edi,FS:[EMSPAGETABLE]
	add	edi,ecx
	dec	edi			
	mov	al,dl
	std				; scan backwards
shrinkpages:
	repnz	scas BYTE PTR [edi]
	mov	BYTE PTR [edi+1],FREEPAGE_ID
	inc	FS:[_PAGESAVAIL]
	dec	bx
	jnz	shrinkpages

realloc_success:
	pop	bx
	xor	ah,ah		; no error occurred
	ret

toomany:
	mov	ah,88h
	mov	bx,di		; return original pages owned by handle
	ret
ems4_realloc ENDP

;
; AH = 52h: EMS 4.0 attribute related
;
ems4_attribute PROC NEAR
	cmp	al,2	; only subfunction 2 supported
	jb	NOT_IMPL
	ja	bad_subfunc	; this is an invalid subfunction

	xor	ax,ax	; al == 0, volatile attribute only, ah == successful call
	ret
ems4_attribute ENDP

;
; AH = 53h: EMS 4.0 get/set handle name
;
ems4_handle_names PROC NEAR
	cmp	al,1	; only subfunction 0 supported
	ja	bad_subfunc	; this is an invalid subfunction
	je	NOT_IMPL

; perform handle check here so that stack return address isn't blown
;  on invalid handle MAP_HANDLE_PAGE call which directly manipulates it
	call	TEST_HANDLE

	movzx	esi,WORD PTR [V8086_ES]	; ES from the Level-0-Stack
	shl	esi,4
	movzx	edi,di
	add	edi,esi	; edi -> handle name buffer address
	xor	esi,esi
	mov	[edi],esi	; handle names are always all zero for now
	mov	[edi+4],esi
	mov	[edi+8],si

	xor	ah,ah	; no error return
	ret
ems4_handle_names ENDP

;
; AH = 54h: EMS 4.0 get various handle info
;
ems4_get_handle_info PROC NEAR
	cmp	al,2	; only subfunction 2 supported
	jb	NOT_IMPL
	ja	bad_subfunc	; this is an invalid subfunction

	mov	bx,255
	mov	ah,bh	; zero ah, no error return
	ret
ems4_get_handle_info ENDP

;
; AH = 57h: EMS 4.0 move/exchange memory region
;
ems4_memory_region PROC NEAR
	movzx	edi,WORD PTR [V8086_DS]	; DS from the Level-0-Stack
	cmp	al,1
	ja	bad_subfunc	; this is an invalid subfunction
	sete	fs:[Xchg_Flag]

; save original EMS page mapping of first two physical pages
	mov	eax,DWORD PTR fs:[PHYSPAGETABLE]
	mov	DWORD PTR fs:[PageMapSave],eax

	push	ebx
	push	edx

	xor	dx,dx		; dh holds counter, dl will bitcode flag src/dest conv/ems
	shl	edi,4
	movzx	esi,si
	add	edi,esi		; edi -> EMS region buffer address
	mov	ecx,[edi]	; get move count
	test	ecx,ecx
	je	mr_good		; always succeeds if no bytes are moved
	mov	ah,96h		; preload error code, region length exceeds 1M
	cmp	ecx,65536*16
	ja	mr_out
	mov	fs:[RegionCount],ecx

; process region destination information
	movzx	ecx,WORD PTR [edi+14]	; offset
	mov	al,[edi+11]	; destination memory type, 0 conv, 1 (nonzero) expanded
	or	al,al
	movzx	ebx,WORD PTR [edi+16]	; keep flag status, preload destination segment if conv
	je	mr_calc_dest

; EMS destination
	mov	dl,2		; bitcode flag EMS destination
	mov	ah,95h		; preload error code, specified offset is outside logical page
	cmp	ecx,4000h-1	; can't have a page offset >16K-1
	ja	mr_out

	add	ecx,4000h	; page 1 is offset 16K from base
	movzx	ebx,fs:[_FRAME]

mr_calc_dest:
	shl	ebx,4		; convert seg to memory offset
	add	ebx,ecx		; ebx -> destination address
	mov	fs:[RegionDest],ebx

; process region source information
	movzx	ecx,WORD PTR [edi+7]	; offset
	mov	al,[edi+4]	; source memory type, 0 conv, 1 (nonzero) expanded
	or	al,al
	movzx	esi,WORD PTR [edi+9]	; keep flag status, preload source segment if conv
	je	mr_calc_src

; EMS source
	or	dl,1		; bitcode flag EMS source
	mov	ah,95h		; preload error code to specified offset is outside logical page
	cmp	ecx,4000h-1	; can't have a page offset >16K-1
	ja	mr_out

	movzx	esi,fs:[_FRAME]

mr_calc_src:
	shl	esi,4		; convert seg to memory offset
	add	esi,ecx		; esi -> source address
	mov	fs:[RegionSource],esi

mr_proc_loop:
	mov	ecx,fs:[RegionCount]
	or	dl,dl		; see if anything is EMS
	je	mr_trans_setup	; nope, bypass EMS calcs
	test	dl,1	; see if source EMS
	je	mr_test_dest	; no

; source boundary check
	movzx	eax,WORD PTR fs:[RegionSource]
	and	ax,3fffh
	mov	ebx,4000h
	sub	ebx,eax		; get bytes available to move/xfer on this page
	cmp	ecx,ebx
	jbe	mr_test_dest
	mov	ecx,ebx		; can't go past page boundary

mr_test_dest:
	test	dl,2	; see if destination EMS
	je	mr_map

; destination boundary check
	movzx	eax,WORD PTR fs:[RegionDest]
	and	ax,3fffh
	mov	ebx,4000h
	sub	ebx,eax		; get bytes available to move/xfer on this page
	cmp	ecx,ebx
	jbe	mr_map
	mov	ecx,ebx		; can't go past page boundary

; now map in the EMS pages, if necessary
mr_map:
	push	ecx
	push	edx
	push	edi
	test	dl,1	; see if source page mapping
	je	mr_map_dest
	movzx	ax,dh	; adjust for pages already transferred
	mov	bx,[edi+9]
	add	bx,ax
	mov	dx,[edi+5]
	mov	al,0
	push	OFFSET bad_map	; offset for code branch if TEST_HANDLE fails
	call	MAP_HANDLE_PAGE
	pop	ax			; remove error code branch offset from stack
	pop	edi			; MAP_HANDLE_PAGE modifies critical edi and edx, restore
	pop	edx
	push	edx
	push	edi

mr_map_dest:
	test	dl,2	; see if destination page mapping
	je	mr_ems_restore
	movzx	ax,dh	; adjust for pages already transferred
	mov	bx,[edi+16]
	add	bx,ax
	mov	dx,[edi+12]
	mov	al,1
	push	OFFSET bad_map	; offset for code branch if TEST_HANDLE fails
	call	MAP_HANDLE_PAGE
	pop	ax			; remove error code branch offset from stack

mr_ems_restore:
	pop	edi
	pop	edx
	pop	ecx			; restore count of bytes to transfer this block
	inc	dh			; increase count of pages transferred

; at this point:
;  dh == page count transferred, if EMS used (+1 from current status)
;  dl == bitcoded flags for source/dest conv/EMS
;  ecx == byte count to transfer
;  edi -> entry buffer
;  RegionSource == address of transfer source
;  RegionDest == address of transfer destination
mr_trans_setup:
	push	ecx
	mov	ebx,edi		; keep pointer to entry buffer
	mov	esi,fs:[RegionSource]
	mov	edi,fs:[RegionDest]
	cmp	fs:[Xchg_Flag],0
	jne	mr_xchg

; use original EMM386 move code instruction block
	MOV     EAX,ECX
	AND     ECX,3
	REP     MOVS BYTE PTR [ESI],BYTE PTR [EDI]
	BIG_NOP
	MOV     ECX,EAX
	SHR     ECX,2
	REP     MOVS DWORD PTR [ESI], DWORD PTR [EDI]
	BIG_NOP

; this block transfer is done, ready for next, if any
mr_trans_done:
	pop	ecx
	mov	eax,fs:[RegionCount]
	sub	eax,ecx
	jz	mr_good		; done
	mov	fs:[RegionCount],eax
	mov	ecx,eax
	cmp	ecx,4000h
	jbe	mr_trans2
	mov	ecx,4000h

mr_trans2:
	mov	fs:[RegionSource],esi	; update source address
	test	dl,1	; see if source EMS
	je	mr_trans3

; subsequent transfer from EMS page base
	movzx	eax,fs:[_FRAME]
	shl	eax,4
	mov	fs:[RegionSource],eax

mr_trans3:
	mov	fs:[RegionDest],edi	; update destination address
	mov	edi,ebx		; restore edi -> entry buffer
	test	dl,2	; see if destination EMS
	je	mr_map

; subsequent transfers to EMS page base+1 page
	movzx	eax,fs:[_FRAME]
	shl	eax,4
	add	eax,4000h
	mov	fs:[RegionDest],eax
	jmp	mr_map

mr_good:
	mov	ah,0	; zero ah, no error return

; restore original page mapping of first two pages and exit
mr_out:
	push	ax
	xor	ax,ax
	mov	bx,fs:[PageMapSave]
	call	MAP_PAGE
	inc	ax
	mov	bx,fs:[PageMapSave+2]
	call	MAP_PAGE
	pop	ax

	pop	edx
	pop	ebx
	ret

mr_xchg:
	push	edx
	mov	edx,ecx
	and	ecx,3
	je	mr_fullx
mr_xsmall:
	mov	al,[esi]
	xchg	al,[edi]
	mov	[esi],al
	inc	edi
	inc	esi
	loop	mr_xsmall
mr_fullx:
	mov	ecx,edx
	shr	ecx,2
mr_xbig:
	mov	eax,[esi]
	xchg	eax,[edi]
	mov	[esi],eax
	add	esi,4
	add	edi,4
	loop	mr_xbig
	pop	edx
	jmp	mr_trans_done

; clear all interim saved registers on stack, info won't be used
bad_map:
	pop	edx
	pop	edx
	pop	edx
	jmp	mr_out

ems4_memory_region ENDP

;
; AH = 58h: EMS 4.0 get addresses of mappable pages, number of mappable pages
;
ems4_get_mappable_info PROC NEAR
	cmp	al,1
	ja	bad_subfunc	; this is an invalid subfunction
	je	nummap

	movzx	esi,WORD PTR [V8086_ES]	; ES from the Level-0-Stack
	shl	esi,4
	movzx	edi,di
	add	edi,esi	; edi -> handle name buffer address
	mov	si,fs:[_FRAME]
	xor	ax,ax
	mov	cx,4

mapinfo_loop:
	mov	[edi],si	; base address
	mov	[edi+2],ax	; physical page
	add	si,400h		; next base address (16384/16 paragraphs) 
	add	edi,4		; next dword entry
	inc	ax			; next physical page
	loop	mapinfo_loop

nummap:
	mov	cx,4	; four mappable pages
	xor	ah,ah	; no error return
	ret

ems4_get_mappable_info ENDP

;
; AH = 59h: EMS 4.0 get hardware config/get number of raw pages
;
ems4_get_config PROC NEAR
	cmp	al,1	; only subfunction 1 supported
	ja	bad_subfunc
	jne	NOT_IMPL

	jmp	GET_UNALLOCATED_PAGE_COUNT

ems4_get_config ENDP

;
; AH = 5ah: EMS 4.0 allocate handle and standard/raw pages
;
ems4_allocate_pages PROC NEAR
	cmp	al,1	; subfunction must be 0 or 1, we don't care if either
	ja	bad_subfunc

	jmp	allocate_pages_plus_zero

ems4_allocate_pages ENDP

;
; AX=DE00: VCPI presence detection
;  return BH = 1 (major version), BL = 0 (minor version)
;
VCPI_Presence	PROC	NEAR
	mov	bx,100h
	xor	ah,ah
	ret
VCPI_Presence	ENDP

;
; AX=DE01: VCPI get protected mode interface
;  entry es:di -> client zero page table (to fill)
;   ds:si -> three descriptor table entries in client's GDT (to fill)
;  return di -> first uninitialized page table entry (advanced by 4K)
;   ebx == offset to server's protect mode code segment
;
VCPI_GetInterface	PROC	NEAR
	movzx	ebx,WORD PTR [V8086_DS]	; DS from the Level-0-Stack
	shl	ebx,4
	movzx	esi,si
	add	esi,ebx			; esi -> client GDT entries
	mov	ebx,OFFSET server_GDT_Code
	mov	eax,fs:[ebx]
	mov	[esi],eax
	mov	eax,fs:[ebx+4]
	mov	[esi+4],eax
	mov	ebx,OFFSET server_GDT_Universe
	mov	eax,fs:[ebx]
	mov	[esi+8],eax
	mov	eax,fs:[ebx+4]
	mov	[esi+12],eax
	mov	ebx,OFFSET server_GDT_Data
	mov	eax,fs:[ebx]
	mov	[esi+16],eax
	mov	eax,fs:[ebx+4]
	mov	[esi+20],eax

	movzx	esi,WORD PTR [V8086_ES]	; ES from the Level-0-Stack
	shl	esi,4
	movzx	edi,di
	add	edi,esi			; edi -> client zero page table
	mov	esi,fs:[PAGEDIR]
	mov	esi,[esi]		; edx -> page table for first 1M
	and	esi,0fffff000h	; mask to page frame address
;	mov	ecx,1000h/4
	mov	ecx,800h/4		; only map first 2M so debugger can stuff in
						; its own PTE's (only ~1.3M needed anyway)

vgiloop:
	mov	eax,[esi]
	and	ax,0F1FFh		; clear bits 9-11
	mov	es:[edi],eax
	add	esi,4
	add	edi,4
	loop	vgiloop

	REP     MOVS DWORD PTR [ESI], DWORD PTR [EDI]
	BIG_NOP

;	add	DWORD PTR [esp+6],1000h	; advance edi value stored on stack
	add	DWORD PTR [esp+6],800h	; advance edi value stored on stack

	mov	ebx,OFFSET PM_ENTRY
	xor	ah,ah
	ret

VCPI_GetInterface	ENDP

; AX=DE02: VCPI get maximum physical memory address
;  return edx == physical address of higher 4K page available
;
VCPI_GetMax	PROC	NEAR
	movzx	edx,fs:[_MAXPAGES]
	shl	edx,14			; convert to 16K offset
	sub	edx,1000h		; get last allocatable 4K page (up to offset)
	add	edx,fs:[FIRSTPAGE]
	xor	ah,ah			; flag success
	ret
VCPI_GetMax	ENDP

;
; AX=DE03: VCPI get number of free pages
;  return edx == number of free pages
;
VCPI_GetFree	PROC	NEAR
	xor	edx,edx
	mov	esi,fs:[VCPI_Tracking]	; esi->VCPI tracked page bytes
	or	esi,esi
	je	vgf_done		; VCPI has no pages to give
	movzx	ecx,fs:[_MAXPAGES]
	jecxz	vgf_done	; no pages

	shr	cx,1			; 2 EMS pages/tracking page byte

vgf_checksubs:
	mov	al,[esi]
	or	al,al			; no partials on either page
	je	vgf_next
	test	al,0fh
	jne	vgf_2			; partials for this page
	or	al,0fh			; no partials, flag entire page allocated, counted later as free EMS page
vgf_2:
	test	al,0f0h
	jne	vgf_bitcounter
	or	al,0f0h

; count number of reset bits in al as 4K page each
vgf_bitcounter:
	mov	ah,8+1
vgf_bitloop:
	dec	ah
	or	ah,ah
	je	vgf_next
	rcr	al,1
	jc	vgf_bitloop
	inc	edx
	jmp	vgf_bitloop

vgf_next:
	inc	esi				; move to next tracking page byte
	loop	vgf_checksubs

	movzx	eax,fs:[_PAGESAVAIL]
	shl	eax,2			; 4 4K pages per EMS free page
	add	edx,eax

vgf_done:
	xor	ah,ah
	ret
VCPI_GetFree	ENDP

;
; AX=DE04: VCPI allocate a 4K page
;  return edx == physical address of 4K page allocated
;
VCPI_Allocate4K	PROC	NEAR
	mov	esi,fs:[VCPI_Tracking]	; esi->VCPI tracked page bytes
	or	esi,esi
	je	va_nomem		; VCPI has no pages to allocate
	movzx	ecx,fs:[_MAXPAGES]
	or	cx,cx
	je	va_nomem		; no pages
	shr	cx,1			; 2 EMS pages/tracking page byte

va_checksubs:
	mov	al,[esi]
	cmp	al,0ffh
	je	va_next			; both pages full up
	or	al,al
	je	va_next			; neither page used
	cmp	al,0fh			; first page full, second unused
	je	va_next
	cmp	al,0f0h			; check if second page full, first unused
	jne	va_allocpage	; at least one page is partially suballocated for VCPI

va_next:
	inc	esi				; move to next tracking page byte
	loop	va_checksubs

; didn't find any partial allocations we could use, try finding new one
va_newalloc:
	movzx	ecx,fs:[_MAXPAGES]
	mov	edi,fs:[EMSPAGETABLE]
	mov	al,FREEPAGE_ID
	repnz	scas BYTE PTR [edi]
	jnz	va_nomem		; no blank pages found

	dec	edi				; adjust to matching page from page+1
	mov	BYTE PTR [edi],1	; flag 16K EMS page allocated
	dec	fs:[_PAGESAVAIL]	; update available EMS pages

; each tracking page byte tracks 2 16K EMS pages (8 bit-coded 4K pages)
	mov	esi,edi
	sub	esi,fs:[EMSPAGETABLE]	; esi == # of 16K page allocated
	mov	cx,si
	and	cl,1			; mask to 1st or 2nd EMS page in tracking
	shl	cl,2			; cl == 0 or 4 for 1st or 2nd EMS page
	mov	al,0f0h
	rol	al,cl			; al == 0f0h if 1st page, 0fh if 2nd

	shr	esi,1					; 2 EMS pages/tracking page byte
	add	esi,fs:[VCPI_Tracking]	; esi -> tracking byte of allocated page

; al holds bit-coded 4K page allocations in 2 EMS pages, esi->tracking byte
;  al value < 10h means suballocating in first EMS page, otherwise second
;   al is known nonzero and != 0ffh
va_allocpage:
	xor	edx,edx			; init page 4K offset shifted left 12 bits
	cmp	al,0eh
	jbe	va_alloclow		; low page allocation 1-0eh, 0f0-0feh
	cmp	al,0f0h
	jae	va_alloclow
	mov	ah,10h			; high page allocation, 0fh-0efh
	mov	dl,4			; start offset 4 bit shifts in
	jmp	va_testloop

va_alloclow:
	mov	ah,1

va_testloop:
	test	al,ah
	je	va_foundfree
	inc	dx				; bump 4K offset
	shl	ah,1
	je	va_nomem		; couldn't find a free spot
	jmp	SHORT va_testloop

va_foundfree:
	test	[esi],ah
	jne	va_testloop		; shouldn't happen, tracking byte has allocation already marked

; convert esi/edx value to full address
	or	[esi],ah		; mark allocation in tracking byte
	shl	edx,12			; convert to 4K offset
	sub	esi,fs:[VCPI_Tracking]
	shl	esi,15			; each page covers 32K
	add	edx,esi
	add	edx,fs:[FIRSTPAGE]	; edx->physical memory
	xor	ah,ah			; flags no errors
	ret

va_nomem:
	mov	ah,88h
	ret

VCPI_Allocate4K	ENDP

;
; AX=DE05: VCPI free a 4K page
;  entry edx == physical address of 4K page to free
;
VCPI_Free4K	PROC	NEAR
	cmp	fs:[VCPI_Tracking],0
	je	vf_badfree		; VCPI didn't give out any allocations
	mov	esi,edx
	sub	esi,fs:[FIRSTPAGE]
	jc	vf_badfree
	mov	ecx,esi
	shr	esi,14			; convert to 16K pages
	movzx	edi,fs:[_MAXPAGES]
	cmp	esi,edi
	jae	vf_badfree		; past last page on record
	shr	esi,1			; convert to 32K (2 16K pages)
	shr	ecx,12			; get 4K offset
	add	esi,fs:[VCPI_Tracking]	; esi -> tracking page byte to free
	and	cl,7			; cl holds bit position within tracking page byte
	mov	al,1
	rol	al,cl			; get bit in proper position

	test	[esi],al
	je	vf_badfree		; bit already reset/freed allocation, fail

	not	al				; get mask
	and	[esi],al		; reset tracking page bit
	not	al				; restore original bit value

	cmp	al,0fh			; see which page had suballocation freed
	ja	vf_2
	test	BYTE PTR [esi],0fh	; see if page is now completely free
	jne	vf_success
	sub	esi,fs:[VCPI_Tracking]
	shl	esi,1			; 2 pages/byte
vf_free:
	add	esi,fs:[EMSPAGETABLE]	; esi->EMS page table entry for tracking page
	cmp	BYTE PTR [esi],1	; has to be VCPI handle
	jne	vf_badfree			; don't deallocate what you don't own
	mov	BYTE PTR [esi],FREEPAGE_ID
	inc	fs:[_PAGESAVAIL]	; bump count of free EMS pages

vf_success:
	xor	ah,ah			; flag success
	ret

vf_2:
	test	BYTE PTR [esi],0f0h	; see if page is now completely free
	jne	vf_success
	sub	esi,fs:[VCPI_Tracking]
	shl	esi,1			; 2 pages/byte
	inc	esi				; high page
	jmp	vf_free

vf_badfree:
	mov	ah,8ah
	ret

VCPI_Free4K	ENDP

;
; AX=DE06: VCPI get physical address of 4K page in first megabyte
;  entry CX_Save = page number (original cx)
;  return edx == physical address of 4K page
;
VCPI_GetAddress	PROC	NEAR
	movzx	ecx,fs:[CX_Save]
	cmp	cx,256
	jae	vga_bad			; page outside of first megabyte

	mov	eax,0fffff000h
	mov	edx,fs:[PAGEDIR]
	mov	edx,[edx]		; edx -> page table for first 1M
	and	edx,eax			; mask to page frame address
	mov	edx,[edx+ecx*4]	; edx == page table entry for page number
	and	edx,eax			; mask to page frame address

	xor	ah,ah			; flag success
	ret

vga_bad:
	mov	ah,8bh
	ret

VCPI_GetAddress	ENDP

;
; AX=DE07: VCPI read CR0
;  return EBX == CR0
;
VCPI_GetCR0	PROC	NEAR
	mov	ebx,cr0
	xor	ah,ah			; flag success
	ret
VCPI_GetCR0	ENDP

;
; AX=DE0A: VCPI get 8259A interrupt vector mappings
;  return bx == 1st vector mapping for master 8259A (IRQ0-IRQ7)
;    cx == 1st vector mapping for slave 8259A (IRQ8-IRQ15)
;
VCPI_GetMappings	PROC	NEAR
	mov	bx,8			; use default
	mov	cx,70h
	mov	[esp+2],cx		; have to save cx value to stack storage
	xor	ah,ah			; flag success
	ret
VCPI_GetMappings	ENDP

; *** NOT IMPLEMENTED
; AX=DE0B: VCPI set 8259A interrupt vector mappings
;  entry bx == 1st vector mapping for master 8259A (IRQ0-IRQ7)
;    cx == 1st vector mapping for slave 8259A (IRQ8-IRQ15)
;
VCPI_SetMappings	PROC	NEAR
	cli					; ensure interrupts disabled

	jmp	NOT_IMPL

VCPI_SetMappings	ENDP

; V86-entry only
; AX=DE0C: VCPI switch from V86 mode to protected mode
;  entry esi -> entry linear address of data structure
;  exit GDTR, IDTR, LDTR, TR loaded for client
;    transfer control to client
;    modify only eax, esi, DS, ES, FS, GS
;
VCPI_V86toPM	PROC	NEAR
	cli					; ensure interrupts disabled
	add	esp,2			; eat dispatch return address
	pop	ecx				; restore stack saved ecx and edi value
	pop	edi
	add	esp,4			; clear esi value off of stack

	mov	eax,cr3
	cmp	eax,[esi].SW_CR3
	je	vvp2			; avoid reloading cr3 if same since it hurts performance
	mov	eax,[esi].SW_CR3	; load cr3 to switch to client's linear address space
;	and	ax,0f018h		; clear out all reserved bits
	mov	cr3,eax

vvp2:
	mov	eax,[esi].SW_GDTOFFS	; set up client's GDT
	DB	66h				; make 32-bit 6-byte load
	lgdt	[eax]
	mov	eax,[esi].SW_IDTOFFS	; set up client's IDT
	DB	66h					; make 32-bit 6-byte load
	lidt	[eax]
	lldt	[esi].SW_LDTR		; set up client's LDT
	mov	eax,[esi].SW_GDTOFFS
	mov	eax,[eax+2]		; EAX == linear base address of client's GDT
	push	ebx
	mov	bx,[esi].SW_TR
	and	ebx,0fff8h
	add	eax,ebx
	pop	ebx
	and	BYTE PTR [eax+5],NOT 2	; clear task busy bit in TSS descriptor
	ltr	[esi].SW_TR				; set up client's TSS
	jmp	PWORD PTR [esi].SW_EIP	; jump to client's entry point

VCPI_V86toPM	ENDP

; protected mode-entry only
; AX=DE0C: VCPI switch from protected mode to V86 mode
;  entry SS:ESP set for IRETD to V86+PM far call return address to discard
;   ds -> linear address space from 0de01h call
;  exit GDTR, IDTR, LDTR, TR loaded for server,
;    SS:ESP and all segment registers loaded with values on stack
;    transfer control to client
;    modify only eax
;
VCPI_PMtoV86	PROC	NEAR
	cli					; client should have disabled interrupts, but not all do

	add	esp,8			; eat far call return address
	mov	DWORD PTR [esp+8],23002h	; set EFLAGS for VM and IOPL=3

	mov	ax,cs
	add	ax,16			; V86_DATA_SEL
	mov	fs,ax
ASSUME fs:MONDATA

	mov	eax,fs:[PAGEDIR]
	mov	cr3,eax			; flush TLB

; set up server system registers
	mov	eax,OFFSET IDT_PTR
	DB	66h					; make 32-bit 6-byte load
	lidt	fs:[eax]
	mov	eax,OFFSET GDT_PTR
	DB	66h					; make 32-bit 6-byte load
	lgdt	fs:[eax]
	mov	ax,V86_LDT_SEL
	lldt	ax

	mov	eax,OFFSET GDT_PTR
	mov	eax,fs:[eax+2]		; EAX == linear base address of server's GDT
	push	ebx
	mov	bx,V86_TSS_SEL
	and	ebx,0fff8h
	add	eax,ebx
	pop	ebx
	and	BYTE PTR [eax+5],NOT 2	; clear task busy bit in TSS descriptor
	mov	ax,V86_TSS_SEL
	ltr	ax

	mov	eax,cr0
	and	al,NOT 8			; ensure TS bit not set
	mov	cr0,eax
	pushfd
	pop	eax
	and	ah,NOT 40h			; ensure NT bit not set
	push	eax
	popfd

	iretd

VCPI_PMtoV86	ENDP

IF	VCPI_DEBUG	EQ	1

VCPI_Debugging	PROC	NEAR
	mov	ax,ds
	movzx	eax,ax
	lsl	eax,eax
	ret
VCPI_Debugging	ENDP

ENDIF

;
; Check a given Handle for validness.
; In case the Handle is invalid the returnaddress is thrown away and afterwards through
; RET returned to dispatcher.

TEST_HANDLE PROC NEAR
        MOV     AH,83H                    ; "Handed over Handle is unknown"
        CMP     DX,MAX_HANDLES            ; Out of area ?
	JAE     SHORT @@BYE
        MOVZX   ESI,DL                    ; Form the pointer from the Handle-Status-
        SHL     ESI,3                     ; Table and ...
	ADD     ESI,FS:[STATUSTABLE]
        CMP     WORD PTR [ESI],-2         ; ... examine, if the Handle has
        JZ      SHORT @@BYE               ; been marked as free
	RET
@@BYE:  POP     SI                        ; Throw away call(ing)-address
		RET
TEST_HANDLE ENDP
;(*-8-*)
V86_LEN         EQU     OFFSET $          ; End of Code-range

V86     ENDS
;
; Installationpart of the virtual Monitor, that later is given back again
; to the system.
;

_TEXT SEGMENT
		extrn _startup_driver:far
		extrn _startup_exe:far
		extrn _finishing_touches:far
_TEXT ENDS


_TEXT SEGMENT
		ASSUME  CS:_TEXT,DS:MONDATA

;*********************************************
; startpoint when executing as EXE
;*********************************************


GO:
	MOV     AX,SEG MONDATA          ; Set up Data segment
	MOV     DS,AX
        MOV     [PSP],ES             ; save PSP for later

	mov     ax, DGROUP
	mov     ds,ax
	mov     ss,ax
	mov     sp, offset DGROUP:exe_stacktop


	push  es		    ; startup_exe(commandline);
	mov   ax,080h

	push  ax
	call  _TEXT:_startup_exe
	add sp,4

				; exit
        mov     ah,04ch         ; that was all
	int 	21h

;***** exe done



;**********************************************
; driver init part
;**********************************************

go_driver_entry proc far

	push ax
	push bx
	push cx
	push dx
	push si
	push bp
	push ds

	mov word ptr es:[di+3	 ],1000h	; STATUS_BAD

	cmp byte ptr es:[di+2],0 		; command == 0 : do we have to initialize?
	jne driver_done


	push es					; request_ptr, needed later
	push di

	call far ptr  go_driver

	pop di
	pop es					; reload address of request header


	or ax,ax				; ax = size of resident code
	jz driver_done

	mov          es:[di+0eh  ],ax   ;
	mov word ptr es:[di+3	 ],0800h ; STATUS_OK


driver_done:
						; we are done,
						; patch the code, calling this
						; driver entry, so we NEVER get called again
	mov bp,sp				;
						; stack frame:
	lds bx, [bp + 14]			; 7*regs, [cs:ip]
	sub bx,5				; call far

	mov byte ptr [bx],0ebh			; JMP $+3
	mov byte ptr [bx+1],03h

	pop ds
	pop bp
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	retf
go_driver_entry ENDP




;struc	request_hdr
;  req_size	db	?		; number of bytes stored
;  unit_id	db	?		; unit ID code
;  cmd		db	?		; command code
;  status	dw	?		; status word
;  rsvd		db	8 dup (?)	; reserved
;ends	request_hdr

;struc	init_strc
;  init_hdr	db	size request_hdr dup (?)
;  units		db	?	; number of supported units
;  end_addr	dd	?		; end address of resident part
;  cmd_line	dd	?		; address of command line
;ends	init_strc

driverss dw 0
driversp dw 0
driverret dw 0

go_driver PROC FAR


	mov cs:[driverret],0
	mov cs:[driverss],ss
	mov cs:[driversp],sp

	mov     ax, DGROUP
	mov     ds,ax
	mov     ss,ax
	mov     sp, offset DGROUP:exe_stacktop

	les ax, es:[di+18]	; fetch driver commandline

	push es                 ; startup_driver(char far *cmdLine)
	push ax
	call _startup_driver
	add sp,4

				;some bugs ??
	or ax,ax
	jnz fail_driver


        XOR     AX,AX           ; next, restore (set back?)
        MOV     DS,AX           ; Reset-Flag
        MOV     AX,00AAh        ; usual OK-message
	MOV     WORD PTR DS:[@Reset_flag],AX
	MOV     AX,SEG MONDATA      ; Set data segment
	MOV     DS,AX


;(*-9-*)

;        MOV     AH,88H               ; determine size of Extended Memory
;        INT     15H
;        MOV     [EXTMEM],AX          ; (in kBytes)

        MOV     AX,3567H              ; save old contents of EMM-Vector
	INT     21H
	MOV     WORD PTR [OLDINT67],BX
	MOV     WORD PTR [OLDINT67+2],ES
	MOV     AX,ES                  ; EMM already installed ?
	OR      AX,BX                  ;
        JZ      Neu_inst               ; if not, the new
;   **** #### **** zusaetzliche Abfrage nach EMMXXXX0 ********
	MOV     DI,10
	MOV     SI,OFFSET Kennung
	CLD
	MOV     CX,8
	REPZ    CMPSB

;	JNZ     Neu_inst
	je	installed		; matched 1st ID string
	mov	di,10			; didn't match, check 2nd ID (NOEMS version)
	mov	si,OFFSET sig2
	mov	cx,8
	repz	cmpsb
	jnz	Neu_inst		; didn't match 2nd ID string

;   **** #### ***********************************************

installed:
	mov 	dx, OFFSET msg_already_installed
	jmp 	ERR_EX

Neu_inst:


        MOV     DX,OFFSET DUMMY_CALL ; install EMM-Vector
	MOV     AX,2567H
	INT     21H
;(*-9-*)
;(#-9-#)
        MOV     AX,3513H                ; Save address of the "old" Disk-
        INT     21H                     ; or Platten-I/O-Interrupts
        MOV     WORD PTR [OLD13],BX     ; and instead of these
        MOV     WORD PTR [OLD13+2],ES   ; hang on the new routine
	MOV     DX,OFFSET NEW13
	MOV     AX,2513H
	INT     21H
	MOV     AX,3540H                ; The pure diskette interrupt
	INT     21H                     ; will not be forgetten for safety reasons!
	MOV     WORD PTR [OLD40],BX
	MOV     WORD PTR [OLD40+2],ES
	MOV     DX,OFFSET NEW40
	MOV     AX,2540H
	INT     21H
;(#-9-#)

        MOV     AX,3515H		    ; save INT 15h (together) with
        INT     21H                 ; Move Block and Extended Size  ...
	MOV     WORD PTR [OLDINT15],BX
	MOV     WORD PTR [OLDINT15+2],ES
        MOV     DX,OFFSET NEW15             ; ... hang up instead new routine
        MOV     AX,2515H
	INT     21H
;
; Adjust table (this programpart takes over the "grateful" task
; to play DDL (Dynamic Linking Loader)

        MOV     CX,4                    ; Totally 4 GDT-Entries have to
        MOV     SI,OFFSET GDT           ; be processed.
        MOV     DX,SEG MONDATA             ; Calculate beginning of DATA-Segment
	MOVZX   EDX,DX
	SHL     EDX,4
GDT_LOOP:
        MOVZX   EBX,WORD PTR [SI+2]	; Read base-address of the Segment
	AND     EBX,EBX                 ; Null ? Then turn into
	JZ      SHORT GDT_LOOP_CONT
	ADD     EBX,EDX
        MOV     [SI+2],BX		; write the Beginning (15..0)
	SHR     EBX,16
        MOV     [SI+4],BL		; Write Bits 23..16
GDT_LOOP_CONT:
        ADD     SI,8                    ; Process next/following entry
	LOOP    GDT_LOOP

	ADD     DWORD PTR [IDT_PTR+2],EDX; Situation of IDT & GDT must
	ADD     DWORD PTR [GDT_PTR+2],EDX; in any case be adjusted.

	MOV     WORD PTR [OFFSET LDT+(V86_DATA_SEL AND 0F8H)+2],DX
	SHR     EDX,16
	MOV     BYTE PTR [OFFSET LDT+(V86_DATA_SEL AND 0F8H)+4],DL

	MOV     DX,SEG RESCODE           ; Register the state of the residenten Code-
	MOVZX   EDX,DX			 ; segments.
	SHL     EDX,4
	MOV     WORD PTR [OFFSET GDT+(REAL_SEL AND 0F8H)+2],DX
	SHR     EDX,16
	MOV     BYTE PTR [OFFSET GDT+(REAL_SEL AND 0F8H)+4],DL

	MOV     DX,SEG V86
	MOVZX   EDX,DX
	SHL     EDX,4
	MOV     WORD PTR [OFFSET LDT+(V86_CODE_SEL AND 0F8H)+2],DX
	SHR     EDX,16
	MOV     BYTE PTR [OFFSET LDT+(V86_CODE_SEL AND 0F8H)+4],DL

        MOV     DX,SEG RES_STACK           ; In any case adapt Stack-Segment
	MOVZX   EDX,DX
	SHL     EDX,4
;	MOV     WORD PTR [OFFSET LDT+(V86_STACK_SEL AND 0F8H)+2],DX
	MOV     WORD PTR [OFFSET GDT+(V86_STACK_SEL AND 0F8H)+2],DX
	SHR     EDX,16
;	MOV     BYTE PTR [OFFSET LDT+(V86_STACK_SEL AND 0F8H)+4],DL
	MOV     BYTE PTR [OFFSET GDT+(V86_STACK_SEL AND 0F8H)+4],DL

	JMP     FAR PTR GO_PROTECTED ; It goes !

ERR_EX: MOV     AH,9
	INT     21H
	jmp fail_driver

;
; In case the switch was succesfull, the remaining commands are
; already executed in virtual 8086-mode

	public KEEP
KEEP:
	mov     ax, DGROUP
	mov     ds,ax
	mov     ss,ax
	mov     sp, offset DGROUP:exe_stacktop


	call  _finishing_touches		; do some postprocessing work

@@IGNORE:
;(*-10-*)
        MOV     AX,OFFSET DRIVERCODE:DATA_END   ; End of resident data range

        add ax,200h                             ; TOM writes -  this is complete bullshit
						; however EXTENSIVE debugging shows, that
						; some bytes after this are later used,
						; probably in the disk transfer area
						; to reproduce, remove line and start with
						; SHELL=
						; you want be very happy %-)
						; this was caused by having not
						; V86_TOS bytes for resident stack


	mov cs:[driverret],ax			; we want that many bytes remaining


						; 1500 byte remaining, return to DOS
;		call PRINT_DEZ

;		MOV     AX,SEG DATA          ; Install data segment
;		MOV     DS,AX

;		MOV     DX,OFFSET MSGF           ; give error message...
;		MOV     AH,9
;		INT     21H


driver_exit:
	mov ss,cs:[driverss]
	mov sp,cs:[driversp]

	mov ax,cs:[driverret]
	retf

fail_driver:
	MOV     AX,SEG MONDATA          ; Install data segment
	MOV     DS,AX

        MOV     DX,OFFSET MSGFail    ; Give/Show/Return errormessage
	MOV     AH,9
	INT     21H

	jmp driver_exit

go_driver ENDP


;
; check, if this program runs after all on a 386-Computer (o.ae.)
; (... you never know)
;
public _IS386
_IS386 PROC NEAR
        PUSHF                        ; save Flags
        XOR     AX,AX                ; first ueberpruefen, if a8086/88
        PUSH    AX                   ; this program abarbeitet, since
        POPF                         ; the PUSHF-command always sets
        PUSHF                        ; the bits 15..12 to 1, the 386
        POP     AX                   ; sets Bit 15 always to Null (0?).
	TEST    AH,80H
	JNZ     SHORT @@NO_386
        MOV     AX,7000H             ; The IOPL-value remains on a 80386
        PUSH    AX                   ; also kept after a POPF
        POPF                         ; a 286 always sets it to Null
	STI
	PUSHF
	POP     AX
	TEST    AX,7000H
	JZ      SHORT @@NO_386
	POPF
	mov ax,1					; OK
	RET
@@NO_386:
	xor ax,ax
	ret
_IS386 ENDP

public _ISPROTECTEDMODE
_ISPROTECTEDMODE proc near
	SMSW    AX
        AND    AX,0001H             ; PE-Bit (Protect Enable) set ?
	ret
_ISPROTECTEDMODE ENDP

;(*-11-*)
;
; Print decimal in AX
;
PRINT_DEZ PROC NEAR
        MOV     BX,10                ; Base (is) 10
        XOR     CX,CX                ; Counter for the amount of digits
@@DIV:  XOR     DX,DX                ; by division & Modulo determine
        DIV     BX                   ; the digits backwards ...
        PUSH    DX                   ; ... and put them on the stack
        AND     AX,AX                ; Something left somewhere?
	LOOPNZ  @@DIV
        NEG     CX                   ; Gives the number of digits
@@PRINT:
        POP     DX                   ; get the single Ziffern again
        ADD     DL,'0'               ; from Stack (now in the
        MOV     AH,2                 ; correct row order)
        INT     21H                  ; and print
	LOOP    @@PRINT
	RET
PRINT_DEZ ENDP
;(*-11-*)

_TEXT ENDS
;
; Stack that's needed shortly after the Installation
;
TMP_STACK SEGMENT PARA USE16
                DB      100H DUP (0)         ; Temporary stack
TMP_TOS EQU     $
TMP_STACK ENDS

_STACK	segment
	my_stack db 1024 dup(?)       ; stack for the C - things

	public exe_stacktop
exe_stacktop dw 0

_STACK	ends


		END     GO
