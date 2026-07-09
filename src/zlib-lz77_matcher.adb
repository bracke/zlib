with Zlib.Deflate_Tables;

package body Zlib.LZ77_Matcher is

   Hash_Size : constant Natural := 32_768;

   subtype Hash_Index is Natural range 0 .. Hash_Size - 1;

   type Head_Table is array (Hash_Index) of Integer;
   type Prev_Table is array (Natural range <>) of Integer;

   function Chain_Limit_For_Level
     (Level : Compression_Level)
      return Natural
     with SPARK_Mode => On
   is
   begin
      case Level is
         when 0 =>
            return 0;
         when 1 =>
            return 4;
         when 2 =>
            return 8;
         when 3 =>
            return 16;
         when 4 =>
            return 32;
         when 5 =>
            return 64;
         when 6 =>
            return 256;
         when 7 =>
            return 1_024;
         when 8 =>
            return 2_048;
         when 9 =>
            return 8_192;
      end case;
   end Chain_Limit_For_Level;

   function Strategy_For_Level
     (Level : Compression_Level)
      return Match_Strategy
     with SPARK_Mode => On
   is
   begin
      case Level is
         when 0 .. 3 =>
            return Greedy;
         when 4 .. 7 =>
            return Lazy;
         when 8 .. 9 =>
            return Optimal;
      end case;
   end Strategy_For_Level;

   function Matching_Enabled_For_Level
     (Level : Compression_Level)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return Chain_Limit_For_Level (Level) > 0;
   end Matching_Enabled_For_Level;

   function Length_Extra_Bits (Length : Natural) return Natural
     with SPARK_Mode => On
   is
   begin
      if Length = Max_Match_Length then
         return 0;
      end if;

      for Symbol in Zlib.Deflate_Tables.Length_Symbol loop
         if Length >= Zlib.Deflate_Tables.Length_Base (Symbol)
           and then
             Length <
             Zlib.Deflate_Tables.Length_Base (Symbol)
             + 2 ** Zlib.Deflate_Tables.Length_Extra (Symbol)
         then
            return Zlib.Deflate_Tables.Length_Extra (Symbol);
         end if;
      end loop;

      return 0;
   end Length_Extra_Bits;

   function Distance_Extra_Bits (Distance : Natural) return Natural
     with SPARK_Mode => On
   is
   begin
      for Symbol in Zlib.Deflate_Tables.Distance_Symbol loop
         if Distance >= Zlib.Deflate_Tables.Distance_Base (Symbol)
           and then
             Distance <
             Zlib.Deflate_Tables.Distance_Base (Symbol)
             + 2 ** Zlib.Deflate_Tables.Distance_Extra (Symbol)
         then
            return Zlib.Deflate_Tables.Distance_Extra (Symbol);
         end if;
      end loop;

      return 13;
   end Distance_Extra_Bits;

   function Token_Cost
     (Len  : Natural;
      Dist : Natural)
     return Natural
     with SPARK_Mode => On
   is
   begin
      if Len = 1 then
         return 9;
      end if;

      return 12 + Length_Extra_Bits (Len) + Distance_Extra_Bits (Dist);
   end Token_Cost;

   function Better_Match
     (Length      : Natural;
      Distance    : Natural;
      Best_Length : Natural;
      Best_Dist   : Natural)
     return Boolean
     with SPARK_Mode => On
   is
   begin
      if Length > Best_Length then
         return True;
      elsif Length < Best_Length or else Length < Min_Match_Length then
         return False;
      end if;

      if Best_Dist = 0 then
         return True;
      end if;

      declare
         Distance_Extra      : constant Natural := Distance_Extra_Bits (Distance);
         Best_Distance_Extra : constant Natural := Distance_Extra_Bits (Best_Dist);
      begin
         return Distance_Extra < Best_Distance_Extra
           or else (Distance_Extra = Best_Distance_Extra and then Distance < Best_Dist);
      end;
   end Better_Match;

   function Hash_At
     (Input : Byte_Array;
      Pos   : Natural)
      return Hash_Index
   is
      B0 : constant Natural := Natural (Input (Input'First + Pos));
      B1 : constant Natural := Natural (Input (Input'First + Pos + 1));
      B2 : constant Natural := Natural (Input (Input'First + Pos + 2));
   begin
      return Hash_Index ((B0 * 257 + B1 * 17 + B2) mod Hash_Size);
   end Hash_At;

   procedure Insert_Position
     (Input : Byte_Array;
      Pos   : Natural;
      Head  : in out Head_Table;
      Prev  : in out Prev_Table)
   is
      H : Hash_Index;
   begin
      if Pos + Min_Match_Length > Input'Length then
         return;
      end if;

      H := Hash_At (Input, Pos);
      Prev (Pos) := Head (H);
      Head (H) := Integer (Pos);
   end Insert_Position;

   procedure Find_Best_Match
     (Input       : Byte_Array;
      Pos         : Natural;
      Head        : Head_Table;
      Prev        : Prev_Table;
      Chain_Limit : Natural;
      Best_Length : out Natural;
      Best_Dist   : out Natural)
   is
      H          : Hash_Index;
      Candidate  : Integer;
      Probes     : Natural := 0;
      Max_Length : constant Natural := Natural'Min (Max_Match_Length, Input'Length - Pos);
   begin
      Best_Length := 0;
      Best_Dist := 0;

      if Chain_Limit = 0 or else Max_Length < Min_Match_Length then
         return;
      end if;

      H := Hash_At (Input, Pos);
      Candidate := Head (H);

      while Candidate >= 0 and then Probes < Chain_Limit loop
         declare
            C      : constant Natural := Natural (Candidate);
            Length : Natural := 0;
         begin
            exit when C >= Pos;

            declare
               Distance : constant Natural := Pos - C;
            begin
               if Distance <= Max_Distance then
                  while Length < Max_Length
                    and then Input (Input'First + C + Length) = Input (Input'First + Pos + Length)
                  loop
                     Length := Length + 1;
                  end loop;

                  if Better_Match (Length, Distance, Best_Length, Best_Dist) then
                     Best_Length := Length;
                     Best_Dist := Distance;
                     exit when Best_Length = Max_Match_Length
                       and then Distance_Extra_Bits (Best_Dist) = 0;
                  end if;
               end if;
            end;

            Candidate := Prev (C);
            Probes := Probes + 1;
         end;
      end loop;
   end Find_Best_Match;

   procedure Emit_Literal
     (Input  : Byte_Array;
      Pos    : Natural;
      Result : in out Token_Array;
      Count  : in out Natural)
   is
   begin
      Result (Count) :=
        (Kind     => Literal,
         Value    => Input (Input'First + Pos),
         Length   => 0,
         Distance => 0);
      Count := Count + 1;
   end Emit_Literal;

   procedure Emit_Match
     (Len    : Natural;
      Dist   : Natural;
      Result : in out Token_Array;
      Count  : in out Natural)
   is
   begin
      pragma Assert (Len in Min_Match_Length .. Max_Match_Length,
                     "lazy/greedy matcher emitted invalid match length");
      pragma Assert (Dist in 1 .. Max_Distance,
                     "lazy/greedy matcher emitted invalid match distance");

      Result (Count) :=
        (Kind     => Match,
         Value    => 0,
         Length   => Len,
         Distance => Dist);
      Count := Count + 1;
   end Emit_Match;

   function Tokenize
     (Input       : Byte_Array;
      Chain_Limit : Natural;
      Strategy    : Match_Strategy)
      return Token_Array
   is
   begin
      if Input'Length = 0 then
         declare
            Empty : constant Token_Array (1 .. 0) := [others => <>];
         begin
            return Empty;
         end;
      end if;

      declare
         Head   : Head_Table := [others => -1];
         Prev   : Prev_Table (0 .. Input'Length - 1) := [others => -1];
         Result : Token_Array (0 .. Input'Length - 1) := [others => <>];
         Count  : Natural := 0;
         Pos    : Natural := 0;
      begin
         if Strategy = Optimal then
            declare
               Best_Lengths : array (0 .. Input'Length - 1) of Natural :=
                 [others => 0];
               Best_Dists   : array (0 .. Input'Length - 1) of Natural :=
                 [others => 0];
               Costs        : array (0 .. Input'Length) of Natural :=
                 [others => 0];
               Choice_Lens  : array (0 .. Input'Length - 1) of Natural :=
                 [others => 1];
               Choice_Dists : array (0 .. Input'Length - 1) of Natural :=
                 [others => 0];
            begin
               for Scan_Pos in 0 .. Input'Length - 1 loop
                  Find_Best_Match
                    (Input, Scan_Pos, Head, Prev, Chain_Limit,
                     Best_Lengths (Scan_Pos), Best_Dists (Scan_Pos));
                  Insert_Position (Input, Scan_Pos, Head, Prev);
               end loop;

               Costs (Input'Length) := 0;
               for Reverse_Pos in reverse 0 .. Input'Length - 1 loop
                  declare
                     Best_Cost : Natural :=
                       Token_Cost (1, 0) + Costs (Reverse_Pos + 1);
                     Best_Len  : Natural := 1;
                     Best_Dist : Natural := 0;
                  begin
                     if Best_Lengths (Reverse_Pos) >= Min_Match_Length then
                        for Len in
                          Min_Match_Length .. Best_Lengths (Reverse_Pos)
                        loop
                           declare
                              Candidate_Cost : constant Natural :=
                                Token_Cost (Len, Best_Dists (Reverse_Pos))
                                + Costs (Reverse_Pos + Len);
                           begin
                              if Candidate_Cost < Best_Cost then
                                 Best_Cost := Candidate_Cost;
                                 Best_Len := Len;
                                 Best_Dist := Best_Dists (Reverse_Pos);
                              end if;
                           end;
                        end loop;
                     end if;

                     Costs (Reverse_Pos) := Best_Cost;
                     Choice_Lens (Reverse_Pos) := Best_Len;
                     Choice_Dists (Reverse_Pos) := Best_Dist;
                  end;
               end loop;

               while Pos < Input'Length loop
                  if Choice_Lens (Pos) >= Min_Match_Length then
                     Emit_Match
                       (Choice_Lens (Pos), Choice_Dists (Pos), Result, Count);
                     Pos := Pos + Choice_Lens (Pos);
                  else
                     Emit_Literal (Input, Pos, Result, Count);
                     Pos := Pos + 1;
                  end if;
               end loop;

               return Result (0 .. Count - 1);
            end;
         end if;

         while Pos < Input'Length loop
            declare
               Len  : Natural;
               Dist : Natural;
            begin
               Find_Best_Match (Input, Pos, Head, Prev, Chain_Limit, Len, Dist);

               if Len < Min_Match_Length then
                  Emit_Literal (Input, Pos, Result, Count);
                  Insert_Position (Input, Pos, Head, Prev);
                  Pos := Pos + 1;

               elsif Strategy = Lazy and then Pos + 1 < Input'Length then
                  declare
                     Next_Len  : Natural;
                     Next_Dist : Natural;
                  begin
                     --  If byte Pos is emitted as a literal, it becomes part
                     --  of the legal history for a match at Pos + 1.  Insert it
                     --  before probing the next position, but do not insert it
                     --  again if the current match is kept.
                     Insert_Position (Input, Pos, Head, Prev);
                     Find_Best_Match
                       (Input, Pos + 1, Head, Prev, Chain_Limit, Next_Len, Next_Dist);

                     if Next_Len > Len
                       or else
                         (Next_Len = Len
                          and then Next_Len >= Min_Match_Length
                          and then
                            Token_Cost (1, 0) +
                            Token_Cost (Next_Len, Next_Dist) <
                            Token_Cost (Len, Dist))
                     then
                        Emit_Literal (Input, Pos, Result, Count);
                        Pos := Pos + 1;
                     else
                        Emit_Match (Len, Dist, Result, Count);

                        for Insert_Pos in
                          Pos + 1 .. Natural'Min (Input'Length - 1, Pos + Len - 1)
                        loop
                           Insert_Position (Input, Insert_Pos, Head, Prev);
                        end loop;

                        Pos := Pos + Len;
                     end if;
                  end;

               else
                  Emit_Match (Len, Dist, Result, Count);

                  for Insert_Pos in Pos .. Natural'Min (Input'Length - 1, Pos + Len - 1) loop
                     Insert_Position (Input, Insert_Pos, Head, Prev);
                  end loop;

                  Pos := Pos + Len;
               end if;
            end;
         end loop;

         return Result (0 .. Count - 1);
      end;
   end Tokenize;

   function Tokenize
     (Input       : Byte_Array;
      Chain_Limit : Natural)
      return Token_Array
   is
   begin
      return Tokenize (Input, Chain_Limit, Greedy);
   end Tokenize;

   function Tokenize_For_Level
     (Input : Byte_Array;
      Level : Compression_Level)
      return Token_Array
   is
   begin
      return Tokenize
        (Input       => Input,
         Chain_Limit => Chain_Limit_For_Level (Level),
         Strategy    => Strategy_For_Level (Level));
   end Tokenize_For_Level;

end Zlib.LZ77_Matcher;
