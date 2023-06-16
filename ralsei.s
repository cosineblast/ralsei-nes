

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
.define ralsei_x $0204
.define ralsei_y $0205

  ;; 0 = up right, 1 = up left, 2 = down left, 3 = down right
.define ralsei_direction $0205

.define is_updating $0204

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

  ;; TODO: hardware: implement safe PPUADDR palette hack

  ;; Copying attribute tables (risky)
  ;; RISK: Taking too long
  ;; TODO: unroll loops

  ;; Preparing Memory & PPU registers
  bit PPUSTATUS

  lda #$23                      ; $23C0: start of attribute table
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

  ;; Waiting for rendering to finish

update:

  @wait_update_start:
  lda is_updating
  beq @wait_update_start



  lda #$00
  sta is_updating

  jmp update
  nop

on_nmi:
  lda ralsei_rendering_done
  beq load_nametable_row
  lda is_updating
  bne nmi_end

  ;; TODO: update uh PPUSCROLL here

  lda #$01
  sta is_updating

nmi_end:
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

  bit PPUSTATUS
  lda #$00
  sta PPUSCROLL

  lda #$00
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
