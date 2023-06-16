

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

  ;; 0: Copying nametable
  ;; 1: Copying attribute table
  ;; 2: Done
.define ralsei_rendering_done $0200
.define background_offset $0201
.define current_addr_high $0202
.define current_addr_low $0203
.define is_updating $0204

.define ralsei_x $0205
.define ralsei_y $0206


  ;; 2 bit value:
  ;; least significant bit determines X, 0 = right, 1 = left
  ;; most signfificant bit determines Y, 0 = down, 1 = up
  ;; 00 = down right
  ;; 01 = down left
  ;; 10 = up right
  ;; 11 = up left
.define ralsei_direction $0207


on_reset:
  sei		; disable IRQs
  cld		; disable decimal mode
  ldx #$40
  stx $4017	; disable APU frame IRQ
  ldx #$ff 	; Set up stack
  txs
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
  ;; Copying color palette
  bit PPUSTATUS

  lda #$3F
  sta PPUADDR

  lda #$00
  sta PPUADDR

  ldx #$00

@loop:
  lda palette_data, x
  sta PPUDATA
  inx
  cpx #$08
  bne @loop

  ;;  PPU Palette hack
  lda #$3F
  sta PPUADDR
  lda #0
  sta PPUADDR
  sta PPUADDR
  sta PPUADDR

  ;; Copying attribute table

  ;; Preparing Memory & PPU registers
  bit PPUSTATUS

  lda #$23                      ; $23DC: attribute table entry for bottom right corner
  sta PPUADDR
  sta current_addr_high


  lda #$DC
  sta PPUADDR
  sta current_addr_low

  ;; Loop Start
  ldx #$00                      ; X: index into pattern table data array

@col_loop:

  ;; Unrolled loop
  lda attribute_data, x
  sta PPUDATA
  inx

  lda attribute_data, x
  sta PPUDATA
  inx

  lda attribute_data, x
  sta PPUDATA
  inx

  lda attribute_data, x
  sta PPUDATA
  inx

  lda current_addr_low
  clc
  adc #$08
  sta current_addr_low
  lda current_addr_high
  adc #$00
  sta current_addr_high

  bit PPUSTATUS
  sta PPUADDR
  lda current_addr_low
  sta PPUADDR

  cpx #$10
  bne @col_loop


  ;; Resetting variables
  lda #$21                      ; 2190 renders ralsei next to bottom right corner
  sta current_addr_high

  lda #$90
  sta current_addr_low

  ;; Enabling rendering

  lda #%00011010	; Enable sprites and background
  sta PPUMASK

  bit PPUSTATUS
  lda #%10000000	; Enable NMI
  sta PPUCTRL

  ;; Update and Render Mechanics

update_loop:

  ;; Waiting for update to start
  @wait_update_start:
  lda is_updating
  beq @wait_update_start

  jsr update

  lda #$00
  sta is_updating
  jmp update_loop
  nop

  ;; update():
  ;;
update:

update_x:
  ldx ralsei_x

  lda #$01
  bit ralsei_direction
  bne @is_left                  ; if (ralsei_direction & 1 == 0) {

  inx                           ;   ralsei_x += 1;
  jmp @end_if                   ; } else {

  @is_left:
  dex                           ;   ralsei_x -= 1;

  @end_if:                      ; }
  stx ralsei_x


  cpx #$7f                      ; if (ralsei_x >= 127) {
  bmi @skip_swap_direction

  lda ralsei_direction          ;   ralsei_direction ^= 1; // swap X bit
  eor #$01
  sta ralsei_direction

  @skip_swap_direction:         ; }

update_y:

  ldx ralsei_y

  lda #$02
  bit ralsei_direction
  bne @is_up                  ; if (ralsei_direction & 2 == 0) {

  inx                           ;   ralsei_y += 1;
  jmp @end_if                   ; } else {

  @is_up:
  dex                           ;   ralsei_y -= 1;

  @end_if:                      ; }
  stx ralsei_y

  bmi @do_swap_direction        ; if ((i8) ralsei_y < 0 || ralsei_x >= $69) {
  cpx #$69                      ; // $69 = selected pixel so that it doesn't go past end of ralsei
  bmi @skip_swap_direction
  @do_swap_direction:

  lda ralsei_direction          ;   ralsei_direction ^= 2; // swap Y bit
  eor #$02
  sta ralsei_direction

  @skip_swap_direction:         ; }

  rts

  ;; render():
  ;;
render:
  ;; Start of ralsei on bottom right is row $C, column $10, base point is
  ;; ($80, $60)

  bit PPUSTATUS

  lda #$80
  clc
  sbc ralsei_x
  sta PPUSCROLL

  lda #$60
  clc
  sbc ralsei_y
  sta PPUSCROLL
  rts

on_nmi:
  ;; Rendering ralsei row if necessary
  lda ralsei_rendering_done
  beq load_nametable_row

  ;; if (!is_updating) {
  lda is_updating
  bne nmi_end

  jsr render                    ; render();

  lda #$01
  sta is_updating               ; is_updating = 1;

nmi_end:
  ;; }
  rti

  nop
load_nametable_row:
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
  ;; updating rendering and update state
  lda #$01
  sta ralsei_rendering_done
  sta is_updating

  ;; setting current PPU address to attribute table start
  bit PPUSTATUS

  lda #$23
  sta PPUADDR
  sta current_addr_high

  lda #$C0
  sta PPUADDR
  sta current_addr_low

  lda #$00
  sta background_offset

end_load:
  ;; Setting PPUSCROLL

  bit PPUSTATUS                 ; ($80, $60) = Ralsei pixel bottom right coordinate
  lda #$80
  sta PPUSCROLL

  lda #$60
  sta PPUSCROLL
  rti

background_content:
  .incbin "ralsei-nametable.bin"

attribute_data:
  .incbin "ralsei-attribute-table.bin"

palette_data:
  .byte $01                     ; background color
  .byte $0f, $2a, $1c           ; palette 0
  .byte $00
  .byte $0f, $30, $25           ; palette 1

.segment "CHARS"

.incbin "ralsei-pattern-table.bin"
