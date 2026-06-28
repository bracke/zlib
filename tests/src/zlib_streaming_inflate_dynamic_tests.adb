with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib;

package body Zlib_Streaming_Inflate_Dynamic_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;

   Base_Text : constant String :=
     "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
     & "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ";

   Dynamic_Stream : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#E5#, 4 => 16#CD#,
      5 => 16#C1#, 6 => 16#0D#, 7 => 16#02#, 8 => 16#31#,
      9 => 16#0C#, 10 => 16#05#, 11 => 16#51#, 12 => 16#4A#,
      13 => 16#F9#, 14 => 16#05#, 15 => 16#A0#, 16 => 16#95#,
      17 => 16#E0#, 18 => 16#46#, 19 => 16#0F#, 20 => 16#7B#,
      21 => 16#A3#, 22 => 16#02#, 23 => 16#27#, 24 => 16#B6#,
      25 => 16#56#, 26 => 16#96#, 27 => 16#E2#, 28 => 16#38#,
      29 => 16#24#, 30 => 16#76#, 31 => 16#FF#, 32 => 16#44#,
      33 => 16#A2#, 34 => 16#0C#, 35 => 16#0A#, 36 => 16#98#,
      37 => 16#37#, 38 => 16#A5#, 39 => 16#79#, 40 => 16#C1#,
      41 => 16#F3#, 42 => 16#F5#, 43 => 16#B8#, 44 => 16#9D#,
      45 => 16#3E#, 46 => 16#C5#, 47 => 16#A0#, 48 => 16#63#,
      49 => 16#A5#, 50 => 16#81#, 51 => 16#BD#, 52 => 16#F9#,
      53 => 16#C4#, 54 => 16#D2#, 55 => 16#00#, 56 => 16#99#,
      57 => 16#C4#, 58 => 16#1D#, 59 => 16#D5#, 60 => 16#FB#,
      61 => 16#92#, 62 => 16#1A#, 63 => 16#12#, 64 => 16#39#,
      65 => 16#41#, 66 => 16#AC#, 67 => 16#43#, 68 => 16#57#,
      69 => 16#D5#, 70 => 16#7E#, 71 => 16#41#, 72 => 16#9A#,
      73 => 16#C6#, 74 => 16#81#, 75 => 16#B7#, 76 => 16#F0#,
      77 => 16#0E#, 78 => 16#20#, 79 => 16#9A#, 80 => 16#CB#,
      81 => 16#9C#, 82 => 16#11#, 83 => 16#62#, 84 => 16#63#,
      85 => 16#C7#, 86 => 16#DA#, 87 => 16#AB#, 88 => 16#B2#,
      89 => 16#72#, 90 => 16#F6#, 91 => 16#40#, 92 => 16#06#,
      93 => 16#1A#, 94 => 16#95#, 95 => 16#CD#, 96 => 16#43#,
      97 => 16#E2#, 98 => 16#47#, 99 => 16#0B#, 100 => 16#8C#,
      101 => 16#AE#, 102 => 16#4E#, 103 => 16#A0#, 104 => 16#A6#,
      105 => 16#9F#, 106 => 16#A4#, 107 => 16#03#, 108 => 16#FF#,
      109 => 16#FA#, 110 => 16#FE#, 111 => 16#02#, 112 => 16#51#,
      113 => 16#25#, 114 => 16#8A#, 115 => 16#F4#];

   Dynamic_Bad_Adler : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#E5#, 4 => 16#CD#,
      5 => 16#C1#, 6 => 16#0D#, 7 => 16#02#, 8 => 16#31#,
      9 => 16#0C#, 10 => 16#05#, 11 => 16#51#, 12 => 16#4A#,
      13 => 16#F9#, 14 => 16#05#, 15 => 16#A0#, 16 => 16#95#,
      17 => 16#E0#, 18 => 16#46#, 19 => 16#0F#, 20 => 16#7B#,
      21 => 16#A3#, 22 => 16#02#, 23 => 16#27#, 24 => 16#B6#,
      25 => 16#56#, 26 => 16#96#, 27 => 16#E2#, 28 => 16#38#,
      29 => 16#24#, 30 => 16#76#, 31 => 16#FF#, 32 => 16#44#,
      33 => 16#A2#, 34 => 16#0C#, 35 => 16#0A#, 36 => 16#98#,
      37 => 16#37#, 38 => 16#A5#, 39 => 16#79#, 40 => 16#C1#,
      41 => 16#F3#, 42 => 16#F5#, 43 => 16#B8#, 44 => 16#9D#,
      45 => 16#3E#, 46 => 16#C5#, 47 => 16#A0#, 48 => 16#63#,
      49 => 16#A5#, 50 => 16#81#, 51 => 16#BD#, 52 => 16#F9#,
      53 => 16#C4#, 54 => 16#D2#, 55 => 16#00#, 56 => 16#99#,
      57 => 16#C4#, 58 => 16#1D#, 59 => 16#D5#, 60 => 16#FB#,
      61 => 16#92#, 62 => 16#1A#, 63 => 16#12#, 64 => 16#39#,
      65 => 16#41#, 66 => 16#AC#, 67 => 16#43#, 68 => 16#57#,
      69 => 16#D5#, 70 => 16#7E#, 71 => 16#41#, 72 => 16#9A#,
      73 => 16#C6#, 74 => 16#81#, 75 => 16#B7#, 76 => 16#F0#,
      77 => 16#0E#, 78 => 16#20#, 79 => 16#9A#, 80 => 16#CB#,
      81 => 16#9C#, 82 => 16#11#, 83 => 16#62#, 84 => 16#63#,
      85 => 16#C7#, 86 => 16#DA#, 87 => 16#AB#, 88 => 16#B2#,
      89 => 16#72#, 90 => 16#F6#, 91 => 16#40#, 92 => 16#06#,
      93 => 16#1A#, 94 => 16#95#, 95 => 16#CD#, 96 => 16#43#,
      97 => 16#E2#, 98 => 16#47#, 99 => 16#0B#, 100 => 16#8C#,
      101 => 16#AE#, 102 => 16#4E#, 103 => 16#A0#, 104 => 16#A6#,
      105 => 16#9F#, 106 => 16#A4#, 107 => 16#03#, 108 => 16#FF#,
      109 => 16#FA#, 110 => 16#FE#, 111 => 16#02#, 112 => 16#51#,
      113 => 16#25#, 114 => 16#8A#, 115 => 16#F5#];

   Dynamic_No_Footer : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#E5#, 4 => 16#CD#,
      5 => 16#C1#, 6 => 16#0D#, 7 => 16#02#, 8 => 16#31#,
      9 => 16#0C#, 10 => 16#05#, 11 => 16#51#, 12 => 16#4A#,
      13 => 16#F9#, 14 => 16#05#, 15 => 16#A0#, 16 => 16#95#,
      17 => 16#E0#, 18 => 16#46#, 19 => 16#0F#, 20 => 16#7B#,
      21 => 16#A3#, 22 => 16#02#, 23 => 16#27#, 24 => 16#B6#,
      25 => 16#56#, 26 => 16#96#, 27 => 16#E2#, 28 => 16#38#,
      29 => 16#24#, 30 => 16#76#, 31 => 16#FF#, 32 => 16#44#,
      33 => 16#A2#, 34 => 16#0C#, 35 => 16#0A#, 36 => 16#98#,
      37 => 16#37#, 38 => 16#A5#, 39 => 16#79#, 40 => 16#C1#,
      41 => 16#F3#, 42 => 16#F5#, 43 => 16#B8#, 44 => 16#9D#,
      45 => 16#3E#, 46 => 16#C5#, 47 => 16#A0#, 48 => 16#63#,
      49 => 16#A5#, 50 => 16#81#, 51 => 16#BD#, 52 => 16#F9#,
      53 => 16#C4#, 54 => 16#D2#, 55 => 16#00#, 56 => 16#99#,
      57 => 16#C4#, 58 => 16#1D#, 59 => 16#D5#, 60 => 16#FB#,
      61 => 16#92#, 62 => 16#1A#, 63 => 16#12#, 64 => 16#39#,
      65 => 16#41#, 66 => 16#AC#, 67 => 16#43#, 68 => 16#57#,
      69 => 16#D5#, 70 => 16#7E#, 71 => 16#41#, 72 => 16#9A#,
      73 => 16#C6#, 74 => 16#81#, 75 => 16#B7#, 76 => 16#F0#,
      77 => 16#0E#, 78 => 16#20#, 79 => 16#9A#, 80 => 16#CB#,
      81 => 16#9C#, 82 => 16#11#, 83 => 16#62#, 84 => 16#63#,
      85 => 16#C7#, 86 => 16#DA#, 87 => 16#AB#, 88 => 16#B2#,
      89 => 16#72#, 90 => 16#F6#, 91 => 16#40#, 92 => 16#06#,
      93 => 16#1A#, 94 => 16#95#, 95 => 16#CD#, 96 => 16#43#,
      97 => 16#E2#, 98 => 16#47#, 99 => 16#0B#, 100 => 16#8C#,
      101 => 16#AE#, 102 => 16#4E#, 103 => 16#A0#, 104 => 16#A6#,
      105 => 16#9F#, 106 => 16#A4#, 107 => 16#03#, 108 => 16#FF#,
      109 => 16#FA#, 110 => 16#FE#, 111 => 16#02#];

   Truncated_Dynamic_Header : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#E5#];

   Invalid_Dynamic_HLIT : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#F5#];

   Truncated_Dynamic_Body : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#05#, 4 => 16#00#,
      5 => 16#80#, 6 => 16#24#];

   Stored_Then_Dynamic : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#00#, 4 => 16#01#,
      5 => 16#00#, 6 => 16#FE#, 7 => 16#FF#, 8 => 16#3F#,
      9 => 16#E5#, 10 => 16#CD#, 11 => 16#C1#, 12 => 16#0D#,
      13 => 16#02#, 14 => 16#31#, 15 => 16#0C#, 16 => 16#05#,
      17 => 16#51#, 18 => 16#4A#, 19 => 16#F9#, 20 => 16#05#,
      21 => 16#A0#, 22 => 16#95#, 23 => 16#E0#, 24 => 16#46#,
      25 => 16#0F#, 26 => 16#7B#, 27 => 16#A3#, 28 => 16#02#,
      29 => 16#27#, 30 => 16#B6#, 31 => 16#56#, 32 => 16#96#,
      33 => 16#E2#, 34 => 16#38#, 35 => 16#24#, 36 => 16#76#,
      37 => 16#FF#, 38 => 16#44#, 39 => 16#A2#, 40 => 16#0C#,
      41 => 16#0A#, 42 => 16#98#, 43 => 16#37#, 44 => 16#A5#,
      45 => 16#79#, 46 => 16#C1#, 47 => 16#F3#, 48 => 16#F5#,
      49 => 16#B8#, 50 => 16#9D#, 51 => 16#3E#, 52 => 16#C5#,
      53 => 16#A0#, 54 => 16#63#, 55 => 16#A5#, 56 => 16#81#,
      57 => 16#BD#, 58 => 16#F9#, 59 => 16#C4#, 60 => 16#D2#,
      61 => 16#00#, 62 => 16#99#, 63 => 16#C4#, 64 => 16#1D#,
      65 => 16#D5#, 66 => 16#FB#, 67 => 16#92#, 68 => 16#1A#,
      69 => 16#12#, 70 => 16#39#, 71 => 16#41#, 72 => 16#AC#,
      73 => 16#43#, 74 => 16#57#, 75 => 16#D5#, 76 => 16#7E#,
      77 => 16#41#, 78 => 16#9A#, 79 => 16#C6#, 80 => 16#81#,
      81 => 16#B7#, 82 => 16#F0#, 83 => 16#0E#, 84 => 16#20#,
      85 => 16#9A#, 86 => 16#CB#, 87 => 16#9C#, 88 => 16#11#,
      89 => 16#62#, 90 => 16#63#, 91 => 16#C7#, 92 => 16#DA#,
      93 => 16#AB#, 94 => 16#B2#, 95 => 16#72#, 96 => 16#F6#,
      97 => 16#40#, 98 => 16#06#, 99 => 16#1A#, 100 => 16#95#,
      101 => 16#CD#, 102 => 16#43#, 103 => 16#E2#, 104 => 16#47#,
      105 => 16#0B#, 106 => 16#8C#, 107 => 16#AE#, 108 => 16#4E#,
      109 => 16#A0#, 110 => 16#A6#, 111 => 16#9F#, 112 => 16#A4#,
      113 => 16#03#, 114 => 16#FF#, 115 => 16#FA#, 116 => 16#FE#,
      117 => 16#02#, 118 => 16#AF#, 119 => 16#28#, 120 => 16#8B#,
      121 => 16#33#];

   Dynamic_Then_Stored : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#EC#, 4 => 16#CD#,
      5 => 16#D1#, 6 => 16#0D#, 7 => 16#C4#, 8 => 16#20#,
      9 => 16#0C#, 10 => 16#04#, 11 => 16#D1#, 12 => 16#56#,
      13 => 16#B6#, 14 => 16#80#, 15 => 16#28#, 16 => 16#95#,
      17 => 16#E4#, 18 => 16#EF#, 19 => 16#2A#, 20 => 16#F0#,
      21 => 16#61#, 22 => 16#2B#, 23 => 16#5A#, 24 => 16#09#,
      25 => 16#03#, 26 => 16#01#, 27 => 16#BB#, 28 => 16#FF#,
      29 => 16#43#, 30 => 16#4A#, 31 => 16#1B#, 32 => 16#57#,
      33 => 16#C0#, 34 => 16#BC#, 35 => 16#B9#, 36 => 16#FA#,
      37 => 16#34#, 38 => 16#07#, 39 => 16#C7#, 40 => 16#4A#,
      41 => 16#87#, 42 => 16#F6#, 43 => 16#DA#, 44 => 16#27#,
      45 => 16#16#, 46 => 16#03#, 47 => 16#E2#, 48 => 16#16#,
      49 => 16#07#, 50 => 16#4A#, 51 => 16#6F#, 52 => 16#CB#,
      53 => 16#4A#, 54 => 16#58#, 55 => 16#E4#, 56 => 16#84#,
      57 => 16#28#, 58 => 16#07#, 59 => 16#57#, 60 => 16#61#,
      61 => 16#BB#, 62 => 16#61#, 63 => 16#95#, 64 => 16#71#,
      65 => 16#E2#, 66 => 16#63#, 67 => 16#BA#, 68 => 16#03#,
      69 => 16#18#, 70 => 16#73#, 71 => 16#79#, 72 => 16#57#,
      73 => 16#84#, 74 => 16#F9#, 75 => 16#D8#, 76 => 16#31#,
      77 => 16#5B#, 78 => 16#A1#, 79 => 16#52#, 80 => 16#B3#,
      81 => 16#05#, 82 => 16#32#, 83 => 16#50#, 84 => 16#E5#,
      85 => 16#BB#, 86 => 16#79#, 87 => 16#58#, 88 => 16#BC#,
      89 => 16#B4#, 90 => 16#C1#, 91 => 16#E5#, 92 => 16#6E#,
      93 => 16#02#, 94 => 16#A9#, 95 => 16#7C#, 96 => 16#52#,
      97 => 16#4E#, 98 => 16#5C#, 99 => 16#FF#, 100 => 16#37#,
      101 => 16#7E#, 102 => 16#01#, 103 => 16#01#, 104 => 16#00#,
      105 => 16#FE#, 106 => 16#FF#, 107 => 16#21#, 108 => 16#E8#,
      109 => 16#2D#, 110 => 16#8D#, 111 => 16#27#];

   Dynamic_Then_Fixed : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#04#, 4 => 16#C0#,
      5 => 16#81#, 6 => 16#08#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#00#, 11 => 16#20#, 12 => 16#B6#,
      13 => 16#FD#, 14 => 16#A5#, 15 => 16#CE#, 16 => 16#39#,
      17 => 16#01#, 18 => 16#00#, 19 => 16#00#, 20 => 16#C6#,
      21 => 16#00#, 22 => 16#84#];

   Dynamic_Empty_Distance_Valid : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#0D#, 4 => 16#80#,
      5 => 16#21#, 6 => 16#09#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#80#, 11 => 16#BC#, 12 => 16#E6#,
      13 => 16#FF#, 14 => 16#53#, 15 => 16#8A#, 16 => 16#01#,
      17 => 16#00#, 18 => 16#42#, 19 => 16#00#, 20 => 16#42#];

   Dynamic_Empty_Distance_Used : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#0D#, 4 => 16#80#,
      5 => 16#21#, 6 => 16#09#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#80#, 11 => 16#BC#, 12 => 16#E6#,
      13 => 16#FF#, 14 => 16#53#, 15 => 16#8A#, 16 => 16#03#,
      17 => 16#00#, 18 => 16#00#, 19 => 16#00#, 20 => 16#00#];

   Dynamic_Invalid_Distance_Symbol : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#0D#, 4 => 16#DE#,
      5 => 16#B1#, 6 => 16#0D#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#C0#, 11 => 16#30#, 12 => 16#A5#,
      13 => 16#A6#, 14 => 16#FC#, 15 => 16#93#, 16 => 16#92#,
      17 => 16#18#, 18 => 16#09#, 19 => 16#3D#, 20 => 16#00#,
      21 => 16#00#, 22 => 16#00#, 23 => 16#00#];

   Invalid_Dynamic_Tree : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#05#, 4 => 16#00#,
      5 => 16#92#, 6 => 16#00#];

   Missing_EOB_Dynamic : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#05#, 4 => 16#C0#,
      5 => 16#81#, 6 => 16#08#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#00#, 11 => 16#20#, 12 => 16#B6#,
      13 => 16#FD#, 14 => 16#AD#, 15 => 16#00#, 16 => 16#00#,
      17 => 16#00#, 18 => 16#00#, 19 => 16#00#];

   Repeat_16_Without_Previous : constant Zlib.Byte_Array :=
     [1 => 16#78#, 2 => 16#9C#, 3 => 16#05#, 4 => 16#00#,
      5 => 16#02#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#00#];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming dynamic-Huffman inflate");
   end Name;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   function Expected_Dynamic_Byte
     (Index : Positive)
      return Zlib.Byte
   is
      Prefix : constant String := "blob 291";
   begin
      if Index <= Prefix'Length then
         return Zlib.Byte (Character'Pos (Prefix (Index)));
      elsif Index = Prefix'Length + 1 then
         return 0;
      else
         return Zlib.Byte
           (Character'Pos
              (Base_Text (((Index - Prefix'Length - 2) mod Base_Text'Length) + 1)));
      end if;
   end Expected_Dynamic_Byte;

   function Expected_Base_Byte
     (Index : Positive)
      return Zlib.Byte
   is
   begin
      return Zlib.Byte
        (Character'Pos (Base_Text (((Index - 1) mod Base_Text'Length) + 1)));
   end Expected_Base_Byte;

   procedure Copy_Output
     (Out_Data : Ada.Streams.Stream_Element_Array;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Result   : in out Zlib.Byte_Array;
      Last     : in out Natural)
   is
   begin
      if Out_Last = Before_First (Out_Data) then
         return;
      end if;

      for I in Out_Data'First .. Out_Last loop
         Last := Last + 1;
         Result (Last) := Zlib.Byte (Out_Data (I));
      end loop;
   end Copy_Output;

   procedure Inflate_Stream
     (Input       : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Result      : in out Zlib.Byte_Array;
      Result_Last : out Natural)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
   begin
      Result_Last := Result'First - 1;
      Zlib.Inflate_Init (Filter);

      while Pos <= Input'Last loop
         declare
            Count    : constant Natural := Natural'Min (Chunk_Size, Input'Last - Pos + 1);
            In_Data  : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            for I in 0 .. Count - 1 loop
               In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                 Ada.Streams.Stream_Element (Input (Pos + I));
            end loop;

            Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);

            if In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;
         end;

         for Guard in 1 .. 10_000 loop
            declare
               Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
               Out_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
            begin
               Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last);
               Copy_Output (Out_Data, Out_Last, Result, Result_Last);
               exit when Out_Last = Before_First (Out_Data);
            end;
         end loop;
      end loop;

      for Guard in 1 .. 10_000 loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            Copy_Output (Out_Data, Out_Last, Result, Result_Last);
            exit when Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "stream end must be true after valid dynamic stream");
      Zlib.Close (Filter);
   end Inflate_Stream;

   procedure Assert_Dynamic_Payload
     (Result : Zlib.Byte_Array;
      Last   : Natural;
      Message : String)
   is
      Expected_Length : constant Natural := 381;
   begin
      Assert (Last = Expected_Length, Message & ": decoded length mismatch");
      for I in 1 .. Expected_Length loop
         Assert
           (Result (I) = Expected_Dynamic_Byte (I),
            Message & ": decoded byte mismatch at" & Natural'Image (I));
      end loop;
   end Assert_Dynamic_Payload;

   procedure Assert_Dynamic_Decodes
     (Input       : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Result : Zlib.Byte_Array (1 .. 512);
      Last   : Natural;
   begin
      Inflate_Stream (Input, Chunk_Size, Output_Size, Result, Last);
      Assert_Dynamic_Payload (Result, Last, Message);
   end Assert_Dynamic_Decodes;

   procedure Expect_Zlib_Error
     (Input  : Zlib.Byte_Array;
      Finish : Boolean)
   is
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 4096);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      for I in Input'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;

      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Translate
           (Filter,
            In_Data,
            In_Last,
            Out_Data,
            Out_Last,
            (if Finish then Zlib.Finish else Zlib.No_Flush));

         if not Raised and then Finish then
            for Guard in 1 .. 32 loop
               declare
                  Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
               begin
                  Zlib.Translate
                    (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
               end;
               exit when Zlib.Stream_End (Filter);
            end loop;
         end if;
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "dynamic invalid/truncated stream must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Expect_Zlib_Error;

   procedure Expect_Flush_Finish_Zlib_Error
     (Input : Zlib.Byte_Array)
   is
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 4096);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      for I in Input'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Input'First + 1)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;

      Zlib.Inflate_Init (Filter);
      Zlib.Translate
        (Filter,
         In_Data,
         In_Last,
         Out_Data,
         Out_Last,
         Zlib.No_Flush);

      begin
         Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Flush(Finish) on truncated dynamic stream must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Expect_Flush_Finish_Zlib_Error;

   procedure Test_Dynamic_Git_Like_Blob
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Dynamic_Decodes (Dynamic_Stream, 128, 64, "dynamic Git-like blob");
   end Test_Dynamic_Git_Like_Blob;

   procedure Test_Dynamic_Input_Byte_By_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Dynamic_Decodes (Dynamic_Stream, 1, 64, "dynamic byte-by-byte input");
   end Test_Dynamic_Input_Byte_By_Byte;

   procedure Test_Dynamic_One_Byte_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Dynamic_Decodes (Dynamic_Stream, 128, 1, "dynamic one-byte output");
   end Test_Dynamic_One_Byte_Output;

   procedure Test_Dynamic_Length_Distance
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Dynamic_Decodes (Dynamic_Stream, 7, 3, "dynamic length/distance payload");
   end Test_Dynamic_Length_Distance;

   procedure Test_Dynamic_Followed_By_Stored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Zlib.Byte_Array (1 .. 512);
      Last   : Natural;
   begin
      Inflate_Stream (Dynamic_Then_Stored, 1, 1, Result, Last);
      Assert (Last = 385, "dynamic block followed by stored block length mismatch");
      for I in 1 .. 384 loop
         Assert (Result (I) = Expected_Base_Byte (I), "dynamic/stored prefix mismatch");
      end loop;
      Assert (Result (385) = Zlib.Byte (Character'Pos ('!')), "dynamic/stored final byte mismatch");
   end Test_Dynamic_Followed_By_Stored;

   procedure Test_Dynamic_Followed_By_Fixed
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Zlib.Byte_Array (1 .. 8);
      Last   : Natural;
   begin
      Inflate_Stream (Dynamic_Then_Fixed, 1, 1, Result, Last);
      Assert (Last = 2, "dynamic block followed by fixed block length mismatch");
      Assert (Result (1) = Zlib.Byte (Character'Pos ('A')),
              "dynamic/fixed dynamic byte mismatch");
      Assert (Result (2) = Zlib.Byte (Character'Pos ('B')),
              "dynamic/fixed fixed byte mismatch");
   end Test_Dynamic_Followed_By_Fixed;

   procedure Test_Stored_Followed_By_Dynamic
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Zlib.Byte_Array (1 .. 512);
      Last   : Natural;
   begin
      Inflate_Stream (Stored_Then_Dynamic, 1, 1, Result, Last);
      Assert (Last = 382, "stored block followed by dynamic block length mismatch");
      Assert (Result (1) = Zlib.Byte (Character'Pos ('?')), "stored/dynamic stored byte mismatch");
      for I in 1 .. 381 loop
         Assert (Result (I + 1) = Expected_Dynamic_Byte (I), "stored/dynamic dynamic byte mismatch");
      end loop;
   end Test_Stored_Followed_By_Dynamic;

   procedure Test_Stream_End_False_Before_Adler
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Dynamic_No_Footer'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 512);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      for I in Dynamic_No_Footer'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I - Dynamic_No_Footer'First + 1)) :=
           Ada.Streams.Stream_Element (Dynamic_No_Footer (I));
      end loop;

      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last);
      Assert (not Zlib.Stream_End (Filter), "Stream_End must remain false before Adler footer");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Stream_End_False_Before_Adler;

   procedure Test_Stream_End_True_After_Adler
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert_Dynamic_Decodes (Dynamic_Stream, 1, 1, "dynamic valid Adler");
   end Test_Stream_End_True_After_Adler;

   procedure Test_Finish_On_Truncated_Dynamic_Header_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Truncated_Dynamic_Header, Finish => True);
   end Test_Finish_On_Truncated_Dynamic_Header_Raises;

   procedure Test_Invalid_Dynamic_HLIT_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Invalid_Dynamic_HLIT, Finish => False);
   end Test_Invalid_Dynamic_HLIT_Raises;

   procedure Test_Finish_On_Truncated_Code_Length_Repeat_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Truncated_Dynamic_Body, Finish => True);
   end Test_Finish_On_Truncated_Code_Length_Repeat_Raises;

   procedure Test_Flush_Finish_On_Truncated_Dynamic_Header_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Flush_Finish_Zlib_Error (Truncated_Dynamic_Header);
   end Test_Flush_Finish_On_Truncated_Dynamic_Header_Raises;

   procedure Test_Flush_Finish_On_Truncated_Code_Length_Repeat_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Flush_Finish_Zlib_Error (Truncated_Dynamic_Body);
   end Test_Flush_Finish_On_Truncated_Code_Length_Repeat_Raises;

   procedure Test_Invalid_Dynamic_Tree_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Invalid_Dynamic_Tree, Finish => False);
   end Test_Invalid_Dynamic_Tree_Raises;

   procedure Test_Missing_EOB_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Missing_EOB_Dynamic, Finish => False);
   end Test_Missing_EOB_Raises;

   procedure Test_Repeat_16_Without_Previous_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Repeat_16_Without_Previous, Finish => False);
   end Test_Repeat_16_Without_Previous_Raises;

   procedure Test_Empty_Distance_Table_With_No_Matches_Decodes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Zlib.Byte_Array (1 .. 8);
      Last   : Natural;
   begin
      Inflate_Stream (Dynamic_Empty_Distance_Valid, 1, 1, Result, Last);
      Assert (Last = 1, "empty distance dynamic literal-only length mismatch");
      Assert (Result (1) = Zlib.Byte (Character'Pos ('A')),
              "empty distance dynamic literal-only byte mismatch");
   end Test_Empty_Distance_Table_With_No_Matches_Decodes;

   procedure Test_Empty_Distance_Table_Used_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Dynamic_Empty_Distance_Used, Finish => False);
   end Test_Empty_Distance_Table_Used_Raises;

   procedure Test_Invalid_Distance_Symbol_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Dynamic_Invalid_Distance_Symbol, Finish => False);
   end Test_Invalid_Distance_Symbol_Raises;

   procedure Test_Invalid_Adler_After_Dynamic_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Expect_Zlib_Error (Dynamic_Bad_Adler, Finish => True);
   end Test_Invalid_Adler_After_Dynamic_Raises;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Dynamic_Git_Like_Blob'Access,
         "streaming dynamic-Huffman Git-like blob fixture");
      Registration.Register_Routine
        (T, Test_Dynamic_Input_Byte_By_Byte'Access,
         "dynamic input split byte-by-byte");
      Registration.Register_Routine
        (T, Test_Dynamic_One_Byte_Output'Access,
         "dynamic input split with one-byte output buffer");
      Registration.Register_Routine
        (T, Test_Dynamic_Length_Distance'Access,
         "dynamic payload with length/distance pair");
      Registration.Register_Routine
        (T, Test_Dynamic_Followed_By_Stored'Access,
         "dynamic block followed by stored block");
      Registration.Register_Routine
        (T, Test_Dynamic_Followed_By_Fixed'Access,
         "dynamic block followed by fixed-Huffman block");
      Registration.Register_Routine
        (T, Test_Stored_Followed_By_Dynamic'Access,
         "stored block followed by dynamic block");
      Registration.Register_Routine
        (T, Test_Stream_End_False_Before_Adler'Access,
         "Dynamic inflate Stream_End false before Adler footer");
      Registration.Register_Routine
        (T, Test_Stream_End_True_After_Adler'Access,
         "Dynamic inflate Stream_End true after valid Adler footer");
      Registration.Register_Routine
        (T, Test_Finish_On_Truncated_Dynamic_Header_Raises'Access,
         "Finish on truncated dynamic header raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Dynamic_HLIT_Raises'Access,
         "invalid dynamic HLIT greater than 286 raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Finish_On_Truncated_Code_Length_Repeat_Raises'Access,
         "Finish on truncated code-length repeat raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Flush_Finish_On_Truncated_Dynamic_Header_Raises'Access,
         "Flush(Finish) on truncated dynamic header raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Flush_Finish_On_Truncated_Code_Length_Repeat_Raises'Access,
         "Flush(Finish) on truncated code-length repeat raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Dynamic_Tree_Raises'Access,
         "invalid dynamic tree raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Missing_EOB_Raises'Access,
         "missing EOB symbol raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Repeat_16_Without_Previous_Raises'Access,
         "repeat symbol 16 without previous length raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Empty_Distance_Table_With_No_Matches_Decodes'Access,
         "empty dynamic distance table decodes literal-only payload");
      Registration.Register_Routine
        (T, Test_Empty_Distance_Table_Used_Raises'Access,
         "distance requested from empty dynamic distance table raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Distance_Symbol_Raises'Access,
         "invalid dynamic distance symbol greater than 29 raises Zlib_Error");
      Registration.Register_Routine
        (T, Test_Invalid_Adler_After_Dynamic_Raises'Access,
         "invalid Adler after dynamic stream raises Zlib_Error");
   end Register_Tests;

end Zlib_Streaming_Inflate_Dynamic_Tests;
