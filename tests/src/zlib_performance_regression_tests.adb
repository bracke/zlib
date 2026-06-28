with Ada.Streams;

with AUnit.Assertions; use AUnit.Assertions;

with Zlib;

package body Zlib_Performance_Regression_Tests is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

   Plain_Length : constant Natural := 70000;

   Large_Zlib_Stream : constant Zlib.Byte_Array :=
     [
      1 => 16#78#, 2 => 16#9C#, 3 => 16#ED#, 4 => 16#CA#,
      5 => 16#59#, 6 => 16#16#, 7 => 16#42#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#00#, 11 => 16#C0#, 12 => 16#13#,
      13 => 16#79#, 14 => 16#4F#, 15 => 16#29#, 16 => 16#71#,
      17 => 16#1C#, 18 => 16#64#, 19 => 16#29#, 20 => 16#CA#,
      21 => 16#96#, 22 => 16#2C#, 23 => 16#A7#, 24 => 16#EF#,
      25 => 16#0C#, 26 => 16#FD#, 27 => 16#CF#, 28 => 16#7C#,
      29 => 16#4F#, 30 => 16#96#, 31 => 16#17#, 32 => 16#F7#,
      33 => 16#B2#, 34 => 16#AA#, 35 => 16#9B#, 36 => 16#C7#,
      37 => 16#B3#, 38 => 16#ED#, 39 => 16#5E#, 40 => 16#EF#,
      41 => 16#7E#, 42 => 16#18#, 43 => 16#A7#, 44 => 16#F9#,
      45 => 16#B3#, 46 => 16#7C#, 47 => 16#D7#, 48 => 16#6D#,
      49 => 16#3F#, 50 => 16#C2#, 51 => 16#D3#, 52 => 16#39#,
      53 => 16#BA#, 54 => 16#5C#, 55 => 16#E3#, 56 => 16#5B#,
      57 => 16#92#, 58 => 16#06#, 59 => 16#41#, 60 => 16#66#,
      61 => 16#59#, 62 => 16#96#, 63 => 16#65#, 64 => 16#59#,
      65 => 16#96#, 66 => 16#65#, 67 => 16#59#, 68 => 16#96#,
      69 => 16#65#, 70 => 16#59#, 71 => 16#96#, 72 => 16#65#,
      73 => 16#59#, 74 => 16#96#, 75 => 16#65#, 76 => 16#59#,
      77 => 16#96#, 78 => 16#65#, 79 => 16#59#, 80 => 16#96#,
      81 => 16#65#, 82 => 16#59#, 83 => 16#96#, 84 => 16#65#,
      85 => 16#59#, 86 => 16#96#, 87 => 16#65#, 88 => 16#59#,
      89 => 16#96#, 90 => 16#65#, 91 => 16#59#, 92 => 16#96#,
      93 => 16#65#, 94 => 16#59#, 95 => 16#96#, 96 => 16#65#,
      97 => 16#59#, 98 => 16#96#, 99 => 16#65#, 100 => 16#59#,
      101 => 16#96#, 102 => 16#65#, 103 => 16#59#, 104 => 16#96#,
      105 => 16#65#, 106 => 16#59#, 107 => 16#96#, 108 => 16#65#,
      109 => 16#59#, 110 => 16#96#, 111 => 16#65#, 112 => 16#59#,
      113 => 16#96#, 114 => 16#65#, 115 => 16#59#, 116 => 16#96#,
      117 => 16#65#, 118 => 16#59#, 119 => 16#96#, 120 => 16#65#,
      121 => 16#59#, 122 => 16#96#, 123 => 16#65#, 124 => 16#59#,
      125 => 16#96#, 126 => 16#65#, 127 => 16#59#, 128 => 16#96#,
      129 => 16#65#, 130 => 16#59#, 131 => 16#96#, 132 => 16#65#,
      133 => 16#59#, 134 => 16#96#, 135 => 16#65#, 136 => 16#59#,
      137 => 16#96#, 138 => 16#65#, 139 => 16#59#, 140 => 16#96#,
      141 => 16#65#, 142 => 16#59#, 143 => 16#96#, 144 => 16#65#,
      145 => 16#59#, 146 => 16#96#, 147 => 16#65#, 148 => 16#59#,
      149 => 16#96#, 150 => 16#65#, 151 => 16#59#, 152 => 16#96#,
      153 => 16#65#, 154 => 16#59#, 155 => 16#96#, 156 => 16#65#,
      157 => 16#59#, 158 => 16#96#, 159 => 16#65#, 160 => 16#59#,
      161 => 16#96#, 162 => 16#65#, 163 => 16#59#, 164 => 16#96#,
      165 => 16#65#, 166 => 16#59#, 167 => 16#96#, 168 => 16#65#,
      169 => 16#59#, 170 => 16#96#, 171 => 16#65#, 172 => 16#59#,
      173 => 16#96#, 174 => 16#65#, 175 => 16#59#, 176 => 16#96#,
      177 => 16#65#, 178 => 16#59#, 179 => 16#96#, 180 => 16#65#,
      181 => 16#59#, 182 => 16#96#, 183 => 16#65#, 184 => 16#59#,
      185 => 16#96#, 186 => 16#65#, 187 => 16#59#, 188 => 16#96#,
      189 => 16#65#, 190 => 16#59#, 191 => 16#96#, 192 => 16#65#,
      193 => 16#59#, 194 => 16#96#, 195 => 16#65#, 196 => 16#59#,
      197 => 16#96#, 198 => 16#65#, 199 => 16#59#, 200 => 16#96#,
      201 => 16#65#, 202 => 16#59#, 203 => 16#96#, 204 => 16#65#,
      205 => 16#59#, 206 => 16#96#, 207 => 16#65#, 208 => 16#59#,
      209 => 16#96#, 210 => 16#65#, 211 => 16#59#, 212 => 16#96#,
      213 => 16#65#, 214 => 16#59#, 215 => 16#96#, 216 => 16#65#,
      217 => 16#59#, 218 => 16#96#, 219 => 16#65#, 220 => 16#59#,
      221 => 16#96#, 222 => 16#65#, 223 => 16#59#, 224 => 16#96#,
      225 => 16#65#, 226 => 16#59#, 227 => 16#96#, 228 => 16#65#,
      229 => 16#59#, 230 => 16#96#, 231 => 16#65#, 232 => 16#59#,
      233 => 16#96#, 234 => 16#65#, 235 => 16#59#, 236 => 16#96#,
      237 => 16#65#, 238 => 16#59#, 239 => 16#96#, 240 => 16#65#,
      241 => 16#59#, 242 => 16#96#, 243 => 16#65#, 244 => 16#59#,
      245 => 16#96#, 246 => 16#65#, 247 => 16#59#, 248 => 16#96#,
      249 => 16#65#, 250 => 16#59#, 251 => 16#96#, 252 => 16#65#,
      253 => 16#59#, 254 => 16#96#, 255 => 16#65#, 256 => 16#59#,
      257 => 16#96#, 258 => 16#65#, 259 => 16#59#, 260 => 16#96#,
      261 => 16#65#, 262 => 16#59#, 263 => 16#D6#, 264 => 16#1F#,
      265 => 16#EB#, 266 => 16#07#, 267 => 16#C7#, 268 => 16#87#,
      269 => 16#55#, 270 => 16#66#
     ];

   Large_GZip_Stream : constant Zlib.Byte_Array :=
     [
      1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#ED#, 12 => 16#CA#,
      13 => 16#59#, 14 => 16#16#, 15 => 16#42#, 16 => 16#00#,
      17 => 16#00#, 18 => 16#00#, 19 => 16#C0#, 20 => 16#13#,
      21 => 16#79#, 22 => 16#4F#, 23 => 16#29#, 24 => 16#71#,
      25 => 16#1C#, 26 => 16#64#, 27 => 16#29#, 28 => 16#CA#,
      29 => 16#96#, 30 => 16#2C#, 31 => 16#A7#, 32 => 16#EF#,
      33 => 16#0C#, 34 => 16#FD#, 35 => 16#CF#, 36 => 16#7C#,
      37 => 16#4F#, 38 => 16#96#, 39 => 16#17#, 40 => 16#F7#,
      41 => 16#B2#, 42 => 16#AA#, 43 => 16#9B#, 44 => 16#C7#,
      45 => 16#B3#, 46 => 16#ED#, 47 => 16#5E#, 48 => 16#EF#,
      49 => 16#7E#, 50 => 16#18#, 51 => 16#A7#, 52 => 16#F9#,
      53 => 16#B3#, 54 => 16#7C#, 55 => 16#D7#, 56 => 16#6D#,
      57 => 16#3F#, 58 => 16#C2#, 59 => 16#D3#, 60 => 16#39#,
      61 => 16#BA#, 62 => 16#5C#, 63 => 16#E3#, 64 => 16#5B#,
      65 => 16#92#, 66 => 16#06#, 67 => 16#41#, 68 => 16#66#,
      69 => 16#59#, 70 => 16#96#, 71 => 16#65#, 72 => 16#59#,
      73 => 16#96#, 74 => 16#65#, 75 => 16#59#, 76 => 16#96#,
      77 => 16#65#, 78 => 16#59#, 79 => 16#96#, 80 => 16#65#,
      81 => 16#59#, 82 => 16#96#, 83 => 16#65#, 84 => 16#59#,
      85 => 16#96#, 86 => 16#65#, 87 => 16#59#, 88 => 16#96#,
      89 => 16#65#, 90 => 16#59#, 91 => 16#96#, 92 => 16#65#,
      93 => 16#59#, 94 => 16#96#, 95 => 16#65#, 96 => 16#59#,
      97 => 16#96#, 98 => 16#65#, 99 => 16#59#, 100 => 16#96#,
      101 => 16#65#, 102 => 16#59#, 103 => 16#96#, 104 => 16#65#,
      105 => 16#59#, 106 => 16#96#, 107 => 16#65#, 108 => 16#59#,
      109 => 16#96#, 110 => 16#65#, 111 => 16#59#, 112 => 16#96#,
      113 => 16#65#, 114 => 16#59#, 115 => 16#96#, 116 => 16#65#,
      117 => 16#59#, 118 => 16#96#, 119 => 16#65#, 120 => 16#59#,
      121 => 16#96#, 122 => 16#65#, 123 => 16#59#, 124 => 16#96#,
      125 => 16#65#, 126 => 16#59#, 127 => 16#96#, 128 => 16#65#,
      129 => 16#59#, 130 => 16#96#, 131 => 16#65#, 132 => 16#59#,
      133 => 16#96#, 134 => 16#65#, 135 => 16#59#, 136 => 16#96#,
      137 => 16#65#, 138 => 16#59#, 139 => 16#96#, 140 => 16#65#,
      141 => 16#59#, 142 => 16#96#, 143 => 16#65#, 144 => 16#59#,
      145 => 16#96#, 146 => 16#65#, 147 => 16#59#, 148 => 16#96#,
      149 => 16#65#, 150 => 16#59#, 151 => 16#96#, 152 => 16#65#,
      153 => 16#59#, 154 => 16#96#, 155 => 16#65#, 156 => 16#59#,
      157 => 16#96#, 158 => 16#65#, 159 => 16#59#, 160 => 16#96#,
      161 => 16#65#, 162 => 16#59#, 163 => 16#96#, 164 => 16#65#,
      165 => 16#59#, 166 => 16#96#, 167 => 16#65#, 168 => 16#59#,
      169 => 16#96#, 170 => 16#65#, 171 => 16#59#, 172 => 16#96#,
      173 => 16#65#, 174 => 16#59#, 175 => 16#96#, 176 => 16#65#,
      177 => 16#59#, 178 => 16#96#, 179 => 16#65#, 180 => 16#59#,
      181 => 16#96#, 182 => 16#65#, 183 => 16#59#, 184 => 16#96#,
      185 => 16#65#, 186 => 16#59#, 187 => 16#96#, 188 => 16#65#,
      189 => 16#59#, 190 => 16#96#, 191 => 16#65#, 192 => 16#59#,
      193 => 16#96#, 194 => 16#65#, 195 => 16#59#, 196 => 16#96#,
      197 => 16#65#, 198 => 16#59#, 199 => 16#96#, 200 => 16#65#,
      201 => 16#59#, 202 => 16#96#, 203 => 16#65#, 204 => 16#59#,
      205 => 16#96#, 206 => 16#65#, 207 => 16#59#, 208 => 16#96#,
      209 => 16#65#, 210 => 16#59#, 211 => 16#96#, 212 => 16#65#,
      213 => 16#59#, 214 => 16#96#, 215 => 16#65#, 216 => 16#59#,
      217 => 16#96#, 218 => 16#65#, 219 => 16#59#, 220 => 16#96#,
      221 => 16#65#, 222 => 16#59#, 223 => 16#96#, 224 => 16#65#,
      225 => 16#59#, 226 => 16#96#, 227 => 16#65#, 228 => 16#59#,
      229 => 16#96#, 230 => 16#65#, 231 => 16#59#, 232 => 16#96#,
      233 => 16#65#, 234 => 16#59#, 235 => 16#96#, 236 => 16#65#,
      237 => 16#59#, 238 => 16#96#, 239 => 16#65#, 240 => 16#59#,
      241 => 16#96#, 242 => 16#65#, 243 => 16#59#, 244 => 16#96#,
      245 => 16#65#, 246 => 16#59#, 247 => 16#96#, 248 => 16#65#,
      249 => 16#59#, 250 => 16#96#, 251 => 16#65#, 252 => 16#59#,
      253 => 16#96#, 254 => 16#65#, 255 => 16#59#, 256 => 16#96#,
      257 => 16#65#, 258 => 16#59#, 259 => 16#96#, 260 => 16#65#,
      261 => 16#59#, 262 => 16#96#, 263 => 16#65#, 264 => 16#59#,
      265 => 16#96#, 266 => 16#65#, 267 => 16#59#, 268 => 16#96#,
      269 => 16#65#, 270 => 16#59#, 271 => 16#D6#, 272 => 16#1F#,
      273 => 16#EB#, 274 => 16#07#, 275 => 16#94#, 276 => 16#2A#,
      277 => 16#48#, 278 => 16#9B#, 279 => 16#70#, 280 => 16#11#,
      281 => 16#01#, 282 => 16#00#
     ];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib performance regression invariants");
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

   function Expected_Byte
     (Index : Natural)
      return Zlib.Byte
   is
      Pattern : constant Zlib.Byte_Array :=
        [Zlib.Byte (Character'Pos ('a')),
         Zlib.Byte (Character'Pos ('b')),
         Zlib.Byte (Character'Pos ('c')),
         Zlib.Byte (Character'Pos ('d')),
         Zlib.Byte (Character'Pos ('e')),
         Zlib.Byte (Character'Pos ('f')),
         Zlib.Byte (Character'Pos ('g')),
         Zlib.Byte (Character'Pos ('h')),
         Zlib.Byte (Character'Pos ('i')),
         Zlib.Byte (Character'Pos ('j')),
         Zlib.Byte (Character'Pos ('k')),
         Zlib.Byte (Character'Pos ('l')),
         Zlib.Byte (Character'Pos ('m')),
         Zlib.Byte (Character'Pos ('n')),
         Zlib.Byte (Character'Pos ('o')),
         Zlib.Byte (Character'Pos ('p')),
         Zlib.Byte (Character'Pos ('q')),
         Zlib.Byte (Character'Pos ('r')),
         Zlib.Byte (Character'Pos ('s')),
         Zlib.Byte (Character'Pos ('t')),
         Zlib.Byte (Character'Pos ('u')),
         Zlib.Byte (Character'Pos ('v')),
         Zlib.Byte (Character'Pos ('w')),
         Zlib.Byte (Character'Pos ('x')),
         Zlib.Byte (Character'Pos ('y')),
         Zlib.Byte (Character'Pos ('z')),
         Zlib.Byte (Character'Pos ('0')),
         Zlib.Byte (Character'Pos ('1')),
         Zlib.Byte (Character'Pos ('2')),
         Zlib.Byte (Character'Pos ('3')),
         Zlib.Byte (Character'Pos ('4')),
         Zlib.Byte (Character'Pos ('5')),
         Zlib.Byte (Character'Pos ('6')),
         Zlib.Byte (Character'Pos ('7')),
         Zlib.Byte (Character'Pos ('8')),
         Zlib.Byte (Character'Pos ('9')),
         Zlib.Byte (Character'Pos ('-')),
         Zlib.Byte (Character'Pos ('-'))];
   begin
      return Pattern (Pattern'First + ((Index - 1) mod Pattern'Length));
   end Expected_Byte;

   procedure Check_Expected
     (Data    : Zlib.Byte_Array;
      Message : String)
   is
   begin
      Assert (Data'Length = Plain_Length, Message & ": output length");

      for I in Data'Range loop
         Assert
           (Data (I) = Expected_Byte (I - Data'First + 1),
            Message & ": byte mismatch");
      end loop;
   end Check_Expected;

   procedure Stream_Decode
     (Input       : Zlib.Byte_Array;
      Header      : Zlib.Header_Type;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Result      : in out Zlib.Byte_Array;
      Result_Last : out Natural)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
   begin
      Result_Last := Result'First - 1;
      Zlib.Inflate_Init (Filter, Header => Header);

      while Pos <= Input'Last loop
         declare
            Count    : constant Natural :=
              Natural'Min (Chunk_Size, Input'Last - Pos + 1);
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

            if Out_Last /= Before_First (Out_Data) then
               for I in Out_Data'First .. Out_Last loop
                  Result_Last := Result_Last + 1;
                  Result (Result_Last) := Zlib.Byte (Out_Data (I));
               end loop;
            end if;

            if In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;
         end;
      end loop;

      for Guard in 1 .. Plain_Length + 100 loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate
              (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);

            if Out_Last /= Before_First (Out_Data) then
               for I in Out_Data'First .. Out_Last loop
                  Result_Last := Result_Last + 1;
                  Result (Result_Last) := Zlib.Byte (Out_Data (I));
               end loop;
            end if;

            exit when Zlib.Stream_End (Filter)
              and then Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "stream must finish");
      Zlib.Close (Filter);
   end Stream_Decode;

   procedure Test_Large_Zlib_Tiny_Buffers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Zlib.Byte_Array (1 .. Plain_Length);
      Last   : Natural;
   begin
      Stream_Decode (Large_Zlib_Stream, Zlib.Zlib_Header, 1, 1, Result, Last);
      Assert (Last = Plain_Length, "large zlib stream output length");
      Check_Expected (Result, "large zlib stream through tiny buffers");
   end Test_Large_Zlib_Tiny_Buffers;

   procedure Test_Large_GZip_Tiny_Buffers
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Zlib.Byte_Array (1 .. Plain_Length);
      Last   : Natural;
   begin
      Stream_Decode (Large_GZip_Stream, Zlib.GZip, 1, 1, Result, Last);
      Assert (Last = Plain_Length, "large gzip stream output length");
      Check_Expected (Result, "large gzip stream through tiny buffers");
   end Test_Large_GZip_Tiny_Buffers;

   procedure Test_One_Shot_And_Streaming_Equivalent
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status   : Zlib.Status_Code;
      One_Shot : constant Zlib.Byte_Array :=
        Zlib.Inflate (Large_Zlib_Stream, Status);
      Streamed : Zlib.Byte_Array (1 .. Plain_Length);
      Last     : Natural;
   begin
      Assert (Status = Zlib.Ok, "one-shot large fixture status");
      Check_Expected (One_Shot, "one-shot large fixture");
      Stream_Decode (Large_Zlib_Stream, Zlib.Zlib_Header, 7, 3, Streamed, Last);
      Assert (Last = One_Shot'Length, "streamed large fixture length");

      for I in One_Shot'Range loop
         Assert (Streamed (I) = One_Shot (I), "large fixture API equivalence");
      end loop;
   end Test_One_Shot_And_Streaming_Equivalent;

   procedure Test_Stored_Stream_Wraps_Window
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Plain  : Zlib.Byte_Array (1 .. Plain_Length);
      Compress_Status : Zlib.Status_Code;
   begin
      for I in Plain'Range loop
         Plain (I) := Expected_Byte (I);
      end loop;

      declare
         Encoded : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Plain, Compress_Status);
         Inflate_Status : Zlib.Status_Code;
         Decoded : constant Zlib.Byte_Array := Zlib.Inflate (Encoded, Inflate_Status);
      begin
         Assert (Compress_Status = Zlib.Ok, "large stored stream compression status");
         Assert (Inflate_Status = Zlib.Ok, "large stored stream inflate status");
         Check_Expected (Decoded, "large stored stream wraps window");
      end;
   end Test_Stored_Stream_Wraps_Window;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Large_Zlib_Tiny_Buffers'Access,
         "large zlib stream decodes through 1-byte buffers");
      Registration.Register_Routine
        (T, Test_Large_GZip_Tiny_Buffers'Access,
         "large gzip stream decodes through 1-byte buffers");
      Registration.Register_Routine
        (T, Test_One_Shot_And_Streaming_Equivalent'Access,
         "large fixture one-shot and streaming outputs are equivalent");
      Registration.Register_Routine
        (T, Test_Stored_Stream_Wraps_Window'Access,
         "large stored stream wraps sliding window correctly");
   end Register_Tests;
end Zlib_Performance_Regression_Tests;
