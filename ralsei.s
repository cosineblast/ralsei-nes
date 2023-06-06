

.segment "HEADER"
  .byte $4E, $45, $53, $1A      ; iNES Header
  .byte 2               ; 2x 16KB PRG code
  .byte 1               ; 1x  8KB CHR data
  .byte $01, $00        ; mapper 0, vertical mirroring

.segment "VECTORS"

    .addr on_nmi                ; on nmi
    .addr on_reset              ; on reset
    .addr 0                     ; IRQ

.segment "STARTUP"              ; unused rn

.segment "CODE"

.define PPUCTRL   $2000
.define PPUMASK   $2001
.define PPUSTATUS $2002
.define OAMADDR   $2003
.define OAMDATA   $2004
.define PPUSCROLL $2005
.define PPUADDR   $2006
.define PPUDATA   $2007

.define is_done_rendering $0200
.define background_offset $0201
.define current_addr_high $0202
.define current_addr_low $0203


on_reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs		;  .
  inx		; now X = 0
  stx PPUCTRL	; disable NMI
  stx PPUMASK 	; disable rendering
  stx $4010 	; disable DMC IRQs


  ;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit PPUSTATUS
  bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory

  ;; second wait for vblank, PPU is ready after this
vblankwait2:
  bit PPUSTATUS
  bpl vblankwait2

main:
  ;; Setting background color.
  bit PPUSTATUS

  lda #$3F
  sta PPUADDR

  lda #$00
  sta PPUADDR

  lda #$05
  sta PPUDATA

  ;; Resetting variables

  lda #$20
  sta current_addr_high

  lda #$00
  sta current_addr_low

  ;; Enabling rendering

  lda #%00011010	; Enable sprites and background
  sta PPUMASK

  bit PPUSTATUS
  lda #%10000000	; Enable NMI
  sta PPUCTRL


forever:
  jmp forever


on_nmi:
  lda is_done_rendering
  beq load_row

  rti


load_row:
  ;; writing nametable address of current row to PPUADDR
  lda PPUSTATUS

  lda current_addr_high
  sta PPUADDR

  lda current_addr_low
  sta PPUADDR

  ldx background_offset
  ldy #$00

  ;; copying one row from PRG-ROM to VRAM
  @loop:

  lda background_content, x
  sta PPUDATA

  inx
  iny
  cpy #$10                    ; $10 = row size
  bne @loop

  ;; adding $10 to background offset
  txa
  beq rendering_done
  sta background_offset

  ;; adding $20 to nametable address
  ;; low byte
  lda current_addr_low
  clc
  adc #$20                    ; $20 = nametable row size
  sta current_addr_low

  ;; high byte, has carry from low byte
  lda current_addr_high
  adc #$00
  sta current_addr_high

  jmp end_load

rendering_done:
  lda #$01
  sta is_done_rendering

end_load:
  ;; Setting PPUSCROLL

  bit PPUSTATUS
  lda #$00
  sta PPUSCROLL

  lda #$00
  sta PPUSCROLL

  rti

background_content:
  .incbin "ralsei-nametable.bin"

palettes:
  .byte $0f, $2a, $1a
  .byte $0f, $30, $25

.segment "CHARS"

.incbin "ralsei-pattern-table.bin"
