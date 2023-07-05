;This is 6502 assembler code for a ProDOS compatible
;Clock Card
;

; Slot x IO locations
YEAR_TENS =     $C082
YEAR_ONES =     $C083
MONTH_TENS =    $C084
MONTH_ONES =    $C085
DAY_WEEK=       $C086
DAY_TENS=       $C087
DAY_ONES=       $C088
HOUR_TENS  =    $C089
HOUR_ONES  =    $C08A
MIN_TENS   =    $C08B
MIN_ONES   =    $C08C
SEC_TENS   =    $C08D
SEC_ONES   =    $C08E

ROMSOFF = $CFFF

; Entry for the clock card
        *=        $C400  ; do we want this? the card shouldn't be anchored to C400
        PHP
        SEI
        PLP
        BIT $FF58
        BVS DOS
READ_ENTRY_4
        CLC
        BCC READ_TIME
WRITE_ENTRY_4
        BNE LBL3
DOS
LBL3
        rts

READ_TIME
        pha

        ; find slot number
        php
        sei
        STA                     ROMSOFF
        lda                     $C089   ; for some reason on prodos 1.0.1 ROM was swapped out
        lda                     $C089
        jsr                     $FF58   ; JSR to the ROM, and we will get the stack back
        tsx
        lda                     $0100,X ; load the slot prefix into the A
        plp
        and                     #$07
        asl                             ; rotate slot prefix into $S0 (left 4 times)
        asl
        asl
        asl
        tax                              ;X will be $S0 for memory locations

	; create a comma delimited string for prodos at 200 - first we put the commas in
        ; format: mo,da,dt,hr,mn
        ; it looks like we can have ,sec at the end
        ;mo is the month (01 = January...12 = December) da is the day of the week (00 = Sunday...06 = Saturday) dt is the date (00 through 31) hr is the hour (00 through 23) mn is the minute (00 through 59)
	; from: https://prodos8.com/docs/techref/adding-routines-to-prodos/


        lda  #','+$80
        sta  $0202
        sta  $0205
        sta  $0208
        sta  $020B
        sta  $020E
        lda  MONTH_TENS,X
        ora  #$80
        sta  $0200
        lda  MONTH_ONES,X
        ora  #$80
        sta  $0201
        lda  #'0'+$80		; Day of week tens is always 0
        sta  $0203
        lda  DAY_WEEK,X
        ora  #$80
        sta  $0204
        lda  DAY_TENS,X
        ora  #$80
        sta  $0206
        lda  DAY_ONES,X
        ora  #$80
        sta  $0207
        lda  HOUR_TENS,X
        ora  #$80
        sta  $0209
        lda  HOUR_ONES,X
        ora  #$80
        sta  $020A
        lda  MIN_TENS,X
        ora  #$80
        sta  $020C
        lda  MIN_ONES,X
        ora  #$80
        sta  $020D
        lda  SEC_TENS,X
        ora  #$80
        sta  $020F
        lda  SEC_ONES,X
        ora  #$80
        sta  $0210
        lda  #$8D			; carrage return
        sta  $0211
        ldx  #$0E
	lda			$C08B    ; turn ROM back off for prodos 1.0.1 ?
	lda			$C08B
        pla
        rts
