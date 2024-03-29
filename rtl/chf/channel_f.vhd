--------------------------------------------------------------------------------
-- Fairchild Channel F console
--------------------------------------------------------------------------------
-- DO 8/2020
--------------------------------------------------------------------------------
-- With help from MAME F8 model

-- 0000  : ROM : sl90025.rom or sl31253.rom
-- 0400  : ROM : sl31254.rom
-- 0800+ : CART

-- COLOR = P[126 + Y*128][2] & P[125 + Y*128][2] & P[X + Y*128][1:0]
  
-- F3850 :   PORT 0 : 7 : NC
--                    6 :                       OUT : ENABLE IN BTN
--                    5 :                       OUT : ARM WRT
--                    4 : NC
--                    3 : IN  : "START"           
--                    2 : IN  : "HOLD"
--                    1 : IN  : "MODE"
--                    0 : IN  : "TIME"
--           PORT 1 : 7 : IN  : "RIGHT G.DOWN"  OUT : WRITE DATA1
--                    6 : IN  : "RIGHT G.UP     OUT : WRITE DATA0
--                    5 : IN  : "RIGHT CW"      OUT : 
--                    4 : IN  : "RIGHT CCW"     OUT : 
--                    3 : IN  : "RIGHT UP"      OUT : 
--                    2 : IN  : "RIGHT DOWN"    OUT : 
--                    1 : IN  : "RIGHT LEFT"    OUT : 
--                    0 : IN  : "RIGHT RIGHT"   OUT : 

-- F3851 :   PORT 4 : 7 : IN  : "LEFT  G.DOWN"  OUT : 
-- SL31253            6 : IN  : "LEFT  G.UP"    OUT : HORIZ BUS 6
--                    5 : IN  : "LEFT  CW"      OUT : HORIZ BUS 5
--                    4 : IN  : "LEFT  CCW"     OUT : HORIZ BUS 4
--                    3 : IN  : "LEFT  UP"      OUT : HORIZ BUS 3
--                    2 : IN  : "LEFT  DOWN"    OUT : HORIZ BUS 2
--                    1 : IN  : "LEFT  LEFT"    OUT : HORIZ BUS 1
--                    0 : IN  : "LEFT  RIGHT"   OUT : HORIZ BUS 0
--           PORT 5 : 7 : IN  :                 OUT : TONE BN
--                    6 : IN  :                 OUT : TONE AN
--                    5 : IN  :                 OUT : VERT  BUS 5
--                    4 : IN  :                 OUT : VERT  BUS 4
--                    3 : IN  :                 OUT : VERT  BUS 3
--                    2 : IN  :                 OUT : VERT  BUS 2
--                    1 : IN  :                 OUT : VERT  BUS 1
--                    0 : IN  :                 OUT : VERT  BUS 0
--            
-- F3851 : No IO
-- SL31254

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;
USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.rom_pack.ALL;
USE work.f8_pack.ALL;

ENTITY chf_core IS
  PORT (
    clk              : IN    std_logic;
    pll_locked       : IN    std_logic;
    
    pal              : IN    std_logic;
    reset            : IN    std_logic;
    
    -- VGA
    vga_clk          : OUT   std_logic;
    vga_ce           : OUT   std_logic;
    vga_r            : OUT   std_logic_vector(7 DOWNTO 0);
    vga_g            : OUT   std_logic_vector(7 DOWNTO 0);
    vga_b            : OUT   std_logic_vector(7 DOWNTO 0);
    vga_hs           : OUT   std_logic; -- positive pulse!
    vga_vs           : OUT   std_logic; -- positive pulse!
    vga_de           : OUT   std_logic; -- = not (VBlank or HBlank)
    
    -- HPS IO
    joystick_0        : IN  unsigned(31 DOWNTO 0);
    joystick_1        : IN  unsigned(31 DOWNTO 0);
    status            : IN  unsigned(31 DOWNTO 0);
    ioctl_download    : IN  std_logic;
    ioctl_index       : IN  std_logic_vector(7 DOWNTO 0);
    ioctl_wr          : IN  std_logic;
    ioctl_addr        : IN  std_logic_vector(24 DOWNTO 0);
    ioctl_dout        : IN  std_logic_vector(7 DOWNTO 0);
    ioctl_wait        : OUT std_logic;
    
    -- AUDIO
    audio_l          : OUT   std_logic_vector(15 DOWNTO 0);
    audio_r          : OUT   std_logic_vector(15 DOWNTO 0)
    );
END chf_core;

ARCHITECTURE struct OF chf_core IS

  SIGNAL ioctl_wait_l,ioctl_download2,ioctl_wr2 : std_logic;
  SIGNAL adrs : uv17;
  
  ----------------------------------------------------------
  SIGNAL dr,dr0,dr1,dr2,dr3,dr4,dr5,dw_cpu : uv8;
  SIGNAL dv0,dv1,dv2,dv3,dv4,dv5,dv_cpu : std_logic;
  SIGNAL romc : uv5;
  SIGNAL phase : uint4;
  SIGNAL ce : std_logic :='0';
  
  SIGNAL pi0_n,po0_n,pi1_n,po1_n,pi1_ni,pi4_n,po4_n,pi4_ni,pi5_n,po5_n : uv8;
  SIGNAL pi24_n,po24_n,pi25_n,po25_n : uv8;
  SIGNAL pi10_n,po10_n,pi11_n,po11_n : uv8;

  SIGNAL ram,rbm : std_logic_vector(0 TO 1023);
  SIGNAL ram_dr,ram_dw,ram_wr,rbm_dr,rbm_dw,rbm_wr : std_logic;
  SIGNAL ram_a,rbm_a : unsigned(9 DOWNTO 0);

  SIGNAL rdena : std_logic;
  SIGNAL load_a : uv10;
  SIGNAL load_d : uv8;
  SIGNAL load_size,load_size_acc : uv16;
  SIGNAL load_wr0,load_wr1,load_wr2,load_wr3 : std_logic;
  SIGNAL tick : std_logic;
  SIGNAL reset_na,areset_na :  std_logic;
  SIGNAL vreset_na : unsigned(0 TO 15);
  
  ----------------------------------------------------------
  CONSTANT INIT_ZERO : arr_uv8(0 TO 1023) := (OTHERS => x"00");

  CONSTANT HDISP      : natural :=208;
  CONSTANT HSYNCSTART : natural :=212;
  CONSTANT HSYNCEND   : natural :=220;
  CONSTANT HTOTAL     : natural :=228;

  CONSTANT VDISP      : natural :=232;
  CONSTANT VSYNCSTART : natural :=242;
  CONSTANT VSYNCEND   : natural :=246;
  CONSTANT VTOTAL     : natural :=262;
  
  -- BLACK WHITE RED GREEN BLUE LTGRAY LTGREEN LTBLUE
  CONSTANT PAL_R : arr_uv8(0 TO 7) :=
    (x"10",x"FD",x"FF",x"02",x"4B",x"E0",x"91",x"CE");
  CONSTANT PAL_G : arr_uv8(0 TO 7) :=
    (x"10",x"FD",x"31",x"CC",x"3F",x"E0",x"FF",x"D0");
  CONSTANT PAL_B : arr_uv8(0 TO 7) :=
    (x"10",x"FD",x"53",x"5D",x"F3",x"E0",x"A6",x"FF");

  TYPE arr_uint3 IS ARRAY(natural RANGE <>) OF uint3;
  CONSTANT CMAP : arr_uint3(0 TO 15) :=
    (0,1,1,1,7,4,2,3,5,4,2,3,6,4,2,3);

  TYPE arr_uv2 IS ARRAY(natural RANGE <>) OF uv2;
  SIGNAL vram : arr_uv2(0 TO 128*64-1); -- Pixels

  SIGNAL vram_a : uint13;
  SIGNAL vram_h : uint7;
  SIGNAL vram_v : uint6;
  SIGNAL vram_dw : uv2;
  SIGNAL vram_wr : std_logic;
  
  SIGNAL v125 : std_logic_vector(0 TO 63);
  SIGNAL v126 : std_logic_vector(0 TO 63);
  
  SIGNAL p125,p125p,p126,p126p : std_logic;
  SIGNAL hpos,hposp : uint8;
  SIGNAL vpos,vposp : uint9;
  SIGNAL pos  : uint13;
  SIGNAL pix : uv2;
  
  SIGNAL vdiv : uv16;
  SIGNAL tone : uv2;
  SIGNAL dc0,pc0,pc1 : uv16;
  SIGNAL acc : uv8;
  SIGNAL visar : uv6;
  SIGNAL iozcs : uv5;
BEGIN
  
  ----------------------------------------------------------
  -- CPU
  
  -- CPUCLK = VIDEOCLK / 2
  ce <='1'; --NOT ce WHEN rising_edge(clk);
  
  i_cpu: ENTITY work.f8_cpu
    PORT MAP (
      dr    => dr,       dw    => dw_cpu,   dv    => dv_cpu,
      romc  => romc,     tick  => tick,     phase => phase,
      po_a_n=> po0_n,    pi_a_n=> pi0_n,    po_b_n => po1_n,      pi_b_n  => pi1_n,
      clk   => clk,      ce    => ce,       reset_na => reset_na,
      acco  => acc,      visaro => visar,   iozcso => iozcs);

  -- PSU SL31253
  i_psu0:ENTITY work.f8_psu
    GENERIC MAP (
      PAGE   => "000000", -- 0x0000
      IOPAGE => "000001", -- Ports 4,5
      IVEC   => x"FFFF",  -- Not used
      ROM    => arr_uv8(INIT_SL31253))
    PORT MAP (
      dw      => dr,     dr      => dr0,     dv      => dv0,
      romc    => romc,   tick    => tick,    phase   => phase,
      ext_int => '0',    int_req => OPEN,    pri_o   => OPEN,  pri_i   => '1',
      po_a_n  => po4_n,  pi_a_n  => pi4_n,   po_b_n  => po5_n, pi_b_n  => pi5_n,
      load_a  => load_a, load_d  => load_d,  load_wr => '0', load_size => load_size,
      clk     => clk,    ce      => ce,      reset_na => reset_na,
      pc0o    => pc0,    pc1o    => pc1,     dc0o     => dc0);

  -- PSU SL31254
  i_psu1:ENTITY work.f8_psu
    GENERIC MAP (
      PAGE   => "000001", -- 0x0400
      IOPAGE => "001001", -- 24/25 : MAZE GAME RAM
      IVEC   => x"FFFF",  -- Not used
      ROM    => arr_uv8(INIT_SL31254))
    PORT MAP (
      dw      => dr,     dr      => dr1,     dv      => dv1,
      romc    => romc,   tick    => tick,    phase   => phase,
      ext_int => '0',    int_req => OPEN,    pri_o   => OPEN,  pri_i   => '1',
      po_a_n  => po24_n, pi_a_n  => pi24_n,  po_b_n  => po25_n, pi_b_n  => pi25_n,
      load_a  => load_a, load_d  => load_d,  load_wr => '0', load_size => load_size,
      clk     => clk,    ce      => ce,      reset_na => reset_na);

  -- CARTRIDGE
  i_psu2:ENTITY work.f8_psu
    GENERIC MAP (
      PAGE   => "000010", -- 0x0800
      IOPAGE => "000100", -- 10/11 : HANGMAN GAME RAM
      IVEC   => x"FFFF",  -- Not used
      ROM    => INIT_ZERO)
    PORT MAP (
      dw      => dr,     dr      => dr2,     dv      => dv2,
      romc    => romc,   tick    => tick,    phase   => phase,
      ext_int => '0',    int_req => OPEN,    pri_o   => OPEN,  pri_i   => '1',
      po_a_n  => po10_n, pi_a_n  => pi10_n,  po_b_n  => po11_n, pi_b_n  => pi11_n,
      load_a  => load_a, load_d  => load_d,  load_wr => load_wr0, load_size => load_size,
      clk     => clk,    ce      => ce,      reset_na => reset_na);

  -- CARTRIDGE
  i_psu3:ENTITY work.f8_psu
    GENERIC MAP (
      PAGE   => "000011", -- 0x0C00
      IOPAGE => "111101", -- Not used
      IVEC   => x"FFFF",  -- Not used
      ROM    => INIT_ZERO)
    PORT MAP (
      dw      => dr,     dr      => dr3,     dv      => dv3,
      romc    => romc,   tick    => tick,    phase   => phase,
      ext_int => '0',    int_req => OPEN,    pri_o   => OPEN,  pri_i   => '1',
      po_a_n  => OPEN,   pi_a_n  => x"FF",   po_b_n  => OPEN,  pi_b_n  => x"FF",
      load_a  => load_a, load_d  => load_d,  load_wr => load_wr1, load_size => load_size,
      clk     => clk,    ce      => ce,      reset_na => reset_na);
  
  -- CARTRIDGE
  i_psu4:ENTITY work.f8_psu
    GENERIC MAP (
      PAGE   => "000100", -- 0x1000
      IOPAGE => "111100", -- Not used
      IVEC   => x"FFFF",  -- Not used
      ROM    => INIT_ZERO)
    PORT MAP (
      dw      => dr,     dr      => dr4,     dv      => dv4,
      romc    => romc,   tick    => tick,    phase   => phase,
      ext_int => '0',    int_req => OPEN,    pri_o   => OPEN,  pri_i   => '1',
      po_a_n  => OPEN,   pi_a_n  => x"FF",   po_b_n  => OPEN,  pi_b_n  => x"FF",
      load_a  => load_a, load_d  => load_d,  load_wr => load_wr2, load_size => load_size,
      clk     => clk,    ce      => ce,      reset_na => reset_na);
  
  -- CARTRIDGE
  i_psu5:ENTITY work.f8_psu
    GENERIC MAP (
      PAGE   => "000101", -- 0x1400
      IOPAGE => "111011", -- Not used
      IVEC   => x"FFFF",  -- Not used
      ROM    => INIT_ZERO)
    PORT MAP (
      dw      => dr,     dr      => dr5,     dv      => dv5,
      romc    => romc,   tick    => tick,    phase   => phase,
      ext_int => '0',    int_req => OPEN,    pri_o   => OPEN,  pri_i   => '1',
      po_a_n  => OPEN,   pi_a_n  => x"FF",   po_b_n  => OPEN,  pi_b_n  => x"FF",
      load_a  => load_a, load_d  => load_d,  load_wr => load_wr3, load_size => load_size,
      clk     => clk,    ce      => ce,      reset_na => reset_na);
  
  dr <= dr0 WHEN dv0='1' ELSE
        dr1 WHEN dv1='1' ELSE
        dr2 WHEN dv2='1' ELSE
        dr3 WHEN dv3='1' ELSE
        dr4 WHEN dv4='1' ELSE
        dr5 WHEN dv5='1' ELSE
        dw_cpu;
  
  ----------------------------------------------------------
  --  MAZE,   HANGMAN : 1kb RAM
  -- port 24     10   : 0 : RW
  -- port 24     10   : 1 : A3
  -- port 24     10   : 2 : A2
  -- port 24     10   : 3 : DATA WRITE
  -- port 24     10   : 4 :
  -- port 24     10   : 5 :
  -- port 24     10   : 6 :
  -- port 24     10   : 7 : DATA READ
  -- port 25     11   : 0 : A0
  -- port 25     11   : 1 : A4
  -- port 25     11   : 2 : A5
  -- port 25     11   : 3 : A6
  -- port 25     11   : 4 : A1
  -- port 25     11   : 5 : A7
  -- port 25     11   : 6 : A8
  -- port 25     11   : 7 : A9

  PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      ram_dr<=ram(to_integer(ram_a(9 DOWNTO 0)));
      
      IF ram_wr='1' THEN
        ram(to_integer(ram_a))<=ram_dw;
      END IF;
    END IF;
  END PROCESS;

  ram_wr <= NOT po24_n(0);
  ram_dw <= po24_n(3);
  ram_a  <= po25_n & po24_n(1) & po24_n(2);
  pi24_n(7) <= ram_dr;
  pi24_n(6 DOWNTO 0) <= po24_n(6 DOWNTO 0);
  pi25_n <= po25_n;

  PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      rbm_dr<=rbm(to_integer(rbm_a(9 DOWNTO 0)));
      
      IF rbm_wr='1' THEN
        rbm(to_integer(rbm_a))<=rbm_dw;
      END IF;
    END IF;
  END PROCESS;

  rbm_wr <= NOT po10_n(0);
  rbm_dw <= po10_n(3);
  rbm_a  <= po11_n & po10_n(1) & po10_n(2);
  pi10_n(7) <= rbm_dr;
  pi10_n(6 DOWNTO 0) <= po10_n(6 DOWNTO 0);
  pi11_n <= po11_n;

  ----------------------------------------------------------
  -- CARTRIDGE LOAD
  
  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      load_a  <=unsigned(ioctl_addr(9 DOWNTO 0));
      load_wr0<=NOT ioctl_addr(10) AND NOT ioctl_addr(11) AND ioctl_wr;
      load_wr1<=    ioctl_addr(10) AND NOT ioctl_addr(11) AND ioctl_wr;
      load_wr2<=NOT ioctl_addr(10) AND     ioctl_addr(11) AND ioctl_wr;
      load_wr3<=    ioctl_addr(10) AND     ioctl_addr(11) AND ioctl_wr;
      load_d  <=unsigned(ioctl_dout);
      ioctl_wait<='0';
      IF ioctl_wr='1' THEN
        load_size_acc <= unsigned(ioctl_addr(15 DOWNTO 0));
      END IF;
    END IF;
  END PROCESS;
  
  rdena<=po0_n(6);
  load_size <= load_size_acc + x"0800";
  
  ----------------------------------------------------------
  -- VIDEO
  vram_h <= to_integer(po4_n(6 DOWNTO 0));
  vram_v <= to_integer(po5_n(5 DOWNTO 0));
  vram_dw<= po1_n(7 DOWNTO 6);
  vram_wr<= NOT po0_n(5);
  
  vram_a <= vram_h + vram_v * 128;

  PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF vram_wr='1' THEN
        vram(vram_a)<=vram_dw;
      END IF;
      IF vram_wr='1' AND vram_h=125 THEN
        v125(vram_v)<=vram_dw(1);
      END IF;
      IF vram_wr='1' AND vram_h=126 THEN
        v126(vram_v)<=vram_dw(1);
      END IF;
    END IF;
  END PROCESS;
  
  -- VIDEO SWEEP
  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF ce='1' THEN
        hpos<=hpos+1;
        IF hpos=HTOTAL-1 THEN
          hpos<=0;
          vpos<=vpos+1;
          IF vpos=VTOTAL-1 THEN
            vpos<=0;
          END IF;
        END IF;

        pos<=((vpos/4) MOD 64) * 128 + ((hpos/2 + 4) MOD 128);
        vposp<=vpos;
        hposp<=hpos;
        
        pix <=vram(pos);
        p125<=v125((vposp/4) MOD 64);
        p126<=v126((vposp/4) MOD 64);
        
        vga_r<=std_logic_vector(PAL_R(CMAP(to_integer(p125 & p126 & pix))));
        vga_g<=std_logic_vector(PAL_G(CMAP(to_integer(p125 & p126 & pix))));
        vga_b<=std_logic_vector(PAL_B(CMAP(to_integer(p125 & p126 & pix))));
        vga_de<=to_std_logic(vposp<=VDISP AND hposp<HDISP AND hposp>0);
        
        vga_hs<=to_std_logic(hposp>=HSYNCSTART AND hposp<=HSYNCEND);
        vga_vs<=to_std_logic(vposp>=VSYNCSTART AND vposp<=VSYNCEND);
      END IF;
    END IF;
  END PROCESS;
  
  vga_clk<=clk;
  vga_ce<=ce;
  
  -- 128 x 64 pixels => 102 x 58 visible => 95 x 58 visible
  -- CPU : F video / 2
  --   1.7897725MHz (NTSC)
  --   2.0000000MHz (PAL GEN 1)
  --   1.7734475MHz (PAL GEN 2)
  
  ----------------------------------------------------------
  -- Joysticks / Buttons
  pi0_n(7 DOWNTO 4)<=po0_n(7 DOWNTO 4);
  pi0_n(0) <= joystick_0(4) OR joystick_1(4); -- TIME
  pi0_n(1) <= joystick_0(5) OR joystick_1(5); -- MODE
  pi0_n(2) <= joystick_0(6) OR joystick_1(6); -- HOLD
  pi0_n(3) <= joystick_0(7) OR joystick_1(7); -- START
  
  pi1_ni(7) <= joystick_0(8);    -- RIGHT G.DOWN
  pi1_ni(6) <= joystick_0(9);    -- RIGHT G.UP
  pi1_ni(5) <= joystick_0(10);   -- RIGHT CW
  pi1_ni(4) <= joystick_0(11);   -- RIGHT CCW
  pi1_ni(3) <= joystick_0(3);    -- RIGHT UP
  pi1_ni(2) <= joystick_0(2);    -- RIGHT DOWN
  pi1_ni(1) <= joystick_0(1);    -- RIGHT LEFT
  pi1_ni(0) <= joystick_0(0);    -- RIGHT RIGHT
  
  pi4_ni(7) <= joystick_1(8);    -- LEFT G.DOWN
  pi4_ni(6) <= joystick_1(9);    -- LEFT G.UP
  pi4_ni(5) <= joystick_1(10);   -- LEFT CW
  pi4_ni(4) <= joystick_1(11);   -- LEFT CCW
  pi4_ni(3) <= joystick_1(3);    -- LEFT UP
  pi4_ni(2) <= joystick_1(2);    -- LEFT DOWN
  pi4_ni(1) <= joystick_1(1);    -- LEFT LEFT
  pi4_ni(0) <= joystick_1(0);    -- LEFT RIGHT

  pi1_n<=pi1_ni AND po1_n WHEN rdena='1' ELSE po1_n;
  pi4_n<=pi4_ni AND po4_n WHEN rdena='1' ELSE po4_n;
  
  pi5_n<=po5_n;
  
  ----------------------------------------------------------
  -- Audio
  -- 00 : Silence
  -- 01 : 1kHz
  -- 10 : 500Hz
  -- 11 : 125Hz & 31Hz
  
  tone <=NOT po5_n(7 DOWNTO 6);
  PROCESS (clk) IS
    VARIABLE s_v : std_logic;
  BEGIN
    IF rising_edge(clk) THEN
      vdiv<=vdiv + 1;
      CASE tone IS
        WHEN "00"   => s_v:='0'; -- OFF
        WHEN "01"   => s_v:=vdiv(11); -- 2V
        WHEN "10"   => s_v:=vdiv(12); -- 4V
        WHEN OTHERS => s_v:=vdiv(13) AND vdiv(15); -- 8V & 32V
      END CASE;
      audio_l<=(OTHERS =>s_v);
      audio_r<=(OTHERS =>s_v);
      
    END IF;
  END PROCESS;
  
  ----------------------------------------------------------
  areset_na<=NOT reset AND pll_locked AND NOT ioctl_download;
  vreset_na<=x"0000" WHEN areset_na='0' ELSE
             '1' & vreset_na(0 TO 14) WHEN rising_edge(clk);
  reset_na<=vreset_na(15);
  
  ----------------------------------------------------------
--pragma synthesis_off
  PROCESS IS
    FILE fil : text OPEN write_mode IS "cpu.log";
    VARIABLE char_v : character;
    VARIABLE lin : line;
    VARIABLE op : uv8;
  BEGIN
    wure(clk,10);
    LOOP
      wure(clk);
      IF phase=4 AND romc=0 THEN
        write(lin,to_hstring(pc0));
        write(lin,string'(" : "));
        write(lin,to_hstring(dr));
        op:=dr;
        IF ILEN(to_integer(dr))=1 THEN
          write(lin,string'(" .. .. : "));
        ELSIF ILEN(to_integer(dr))=2 THEN
          wure(clk);
          LOOP
            wure(clk);
            EXIT WHEN phase=4 AND (romc=0 OR romc=1 OR romc=3 OR romc=12 OR romc=14);
          END LOOP;
          write(lin,string'(" "));
          write(lin,to_hstring(dr));
          write(lin,string'(" .. : "));
        ELSIF ILEN(to_integer(dr))=3 THEN
          wure(clk);
          LOOP
            wure(clk);
            EXIT WHEN phase=4 AND (romc=0 OR romc=1 OR romc=3 OR romc=12 OR romc=14);
          END LOOP;
          write(lin,string'(" "));
          write(lin,to_hstring(dr));
          wure(clk);
          LOOP
            wure(clk);
            EXIT WHEN phase=4 AND (romc=0 OR romc=1 OR romc=3 OR romc=12 OR romc=14);
          END LOOP;
          write(lin,string'(" "));
          write(lin,to_hstring(dr));
          write(lin,string'(" : "));
        END IF;
        write(lin,OPTXT(to_integer(op)));
        write(lin,string'(" DC0=") & to_hstring(dc0));
        write(lin,string'(" PC1=") & to_hstring(pc1));
        write(lin,string'(" ACC=") & to_hstring(acc));
        write(lin,string'(" ISAR=") & to_hstring("00" & visar));
        write(lin,string'("  "));
        write(lin,now);
        writeline(fil,lin);
      END IF;
    END LOOP;
    WAIT;
  END PROCESS;

  
--pragma synthesis_on
  
END struct;
