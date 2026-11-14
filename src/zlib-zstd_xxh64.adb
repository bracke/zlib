package body Zlib.Zstd_XXH64 is

   use type Interfaces.Unsigned_64;

   Prime_1 : constant Interfaces.Unsigned_64 := 11_400_714_785_074_694_791;
   Prime_2 : constant Interfaces.Unsigned_64 := 14_029_467_366_897_019_727;
   Prime_3 : constant Interfaces.Unsigned_64 := 1_609_587_929_392_839_161;
   Prime_4 : constant Interfaces.Unsigned_64 := 9_650_029_242_287_828_579;
   Prime_5 : constant Interfaces.Unsigned_64 := 2_870_177_450_012_600_261;

   function Read_64
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64;
   function Read_32
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64;
   function Round
     (Accumulator : Interfaces.Unsigned_64;
      Input       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64;
   function Merge_Round
     (Accumulator : Interfaces.Unsigned_64;
      Value       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64;

   function Read_64
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in reverse 0 .. 7 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Data (At_Index + Offset));
      end loop;
      return Result;
   end Read_64;

   function Read_32
     (Data : Byte_Array; At_Index : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in reverse 0 .. 3 loop
         Result :=
           Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Data (At_Index + Offset));
      end loop;
      return Result;
   end Read_32;

   function Round
     (Accumulator : Interfaces.Unsigned_64;
      Input       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is
      Value : Interfaces.Unsigned_64 := Accumulator;
   begin
      Value := Value + Input * Prime_2;
      Value := Interfaces.Rotate_Left (Value, 31);
      return Value * Prime_1;
   end Round;

   function Merge_Round
     (Accumulator : Interfaces.Unsigned_64;
      Value       : Interfaces.Unsigned_64) return Interfaces.Unsigned_64
   is
      Folded : constant Interfaces.Unsigned_64 := Round (0, Value);
   begin
      return (Accumulator xor Folded) * Prime_1 + Prime_4;
   end Merge_Round;

   procedure Stripe
     (S        : in out State;
      Data     : Byte_Array;
      At_Index : Natural);
   --  Fold one 32-byte stripe, starting at At_Index, into the four lanes.

   procedure Stripe
     (S        : in out State;
      Data     : Byte_Array;
      At_Index : Natural) is
   begin
      S.V1 := Round (S.V1, Read_64 (Data, At_Index));
      S.V2 := Round (S.V2, Read_64 (Data, At_Index + 8));
      S.V3 := Round (S.V3, Read_64 (Data, At_Index + 16));
      S.V4 := Round (S.V4, Read_64 (Data, At_Index + 24));
   end Stripe;

   procedure Reset (S : out State; Seed : Interfaces.Unsigned_64 := 0) is
   begin
      S :=
        (Seed     => Seed,
         V1       => Seed + Prime_1 + Prime_2,
         V2       => Seed + Prime_2,
         V3       => Seed,
         V4       => Seed - Prime_1,
         Total    => 0,
         Pending  => [others => 0],
         Buffered => 0);
   end Reset;

   procedure Update (S : in out State; Data : Byte_Array) is
      Position  : Natural := Data'First;
      Remaining : Natural := Data'Length;
   begin
      S.Total := S.Total + Interfaces.Unsigned_64 (Data'Length);

      --  Top up a stripe left incomplete by the previous call first.
      if S.Buffered > 0 and then Remaining > 0 then
         declare
            Take : constant Natural :=
              Natural'Min (Remaining, S.Pending'Length - S.Buffered);
         begin
            for Offset in 0 .. Take - 1 loop
               S.Pending (S.Buffered + Offset) := Data (Position + Offset);
            end loop;
            Position := Position + Take;
            Remaining := Remaining - Take;

            if S.Buffered + Take = S.Pending'Length then
               declare
                  Full : constant Byte_Array (0 .. 31) := S.Pending;
               begin
                  Stripe (S, Full, Full'First);
               end;
               S.Buffered := 0;
            else
               S.Buffered := S.Buffered + Take;
            end if;
         end;
      end if;

      --  Here either nothing is pending or nothing is left to feed.
      while Remaining >= 32 loop
         Stripe (S, Data, Position);
         Position := Position + 32;
         Remaining := Remaining - 32;
      end loop;

      for Offset in 0 .. Remaining - 1 loop
         S.Pending (S.Buffered + Offset) := Data (Position + Offset);
      end loop;
      S.Buffered := S.Buffered + Remaining;
   end Update;

   function Digest (S : State) return Interfaces.Unsigned_64 is
      Position  : Natural := S.Pending'First;
      Remaining : Natural := S.Buffered;
      Hash      : Interfaces.Unsigned_64;
   begin
      if S.Total >= 32 then
         Hash :=
           Interfaces.Rotate_Left (S.V1, 1)
           + Interfaces.Rotate_Left (S.V2, 7)
           + Interfaces.Rotate_Left (S.V3, 12)
           + Interfaces.Rotate_Left (S.V4, 18);

         Hash := Merge_Round (Hash, S.V1);
         Hash := Merge_Round (Hash, S.V2);
         Hash := Merge_Round (Hash, S.V3);
         Hash := Merge_Round (Hash, S.V4);
      else
         Hash := S.Seed + Prime_5;
      end if;

      Hash := Hash + S.Total;

      while Remaining >= 8 loop
         Hash := Hash xor Round (0, Read_64 (S.Pending, Position));
         Hash := Interfaces.Rotate_Left (Hash, 27) * Prime_1 + Prime_4;
         Position := Position + 8;
         Remaining := Remaining - 8;
      end loop;

      if Remaining >= 4 then
         Hash := Hash xor (Read_32 (S.Pending, Position) * Prime_1);
         Hash := Interfaces.Rotate_Left (Hash, 23) * Prime_2 + Prime_3;
         Position := Position + 4;
         Remaining := Remaining - 4;
      end if;

      while Remaining > 0 loop
         Hash :=
           Hash xor (Interfaces.Unsigned_64 (S.Pending (Position)) * Prime_5);
         Hash := Interfaces.Rotate_Left (Hash, 11) * Prime_1;
         Position := Position + 1;
         Remaining := Remaining - 1;
      end loop;

      Hash := Hash xor Interfaces.Shift_Right (Hash, 33);
      Hash := Hash * Prime_2;
      Hash := Hash xor Interfaces.Shift_Right (Hash, 29);
      Hash := Hash * Prime_3;
      Hash := Hash xor Interfaces.Shift_Right (Hash, 32);

      return Hash;
   end Digest;

   function Compute
     (Data : Byte_Array;
      Seed : Interfaces.Unsigned_64 := 0) return Interfaces.Unsigned_64
   is
      S : State;
   begin
      Reset (S, Seed);
      Update (S, Data);
      return Digest (S);
   end Compute;

end Zlib.Zstd_XXH64;
