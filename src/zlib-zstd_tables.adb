package body Zlib.Zstd_Tables is

   function Highest_Bit (Value : Natural) return Natural is
      Result : Natural := 0;
      Scan   : Natural := Value;
   begin
      while Scan > 1 loop
         Scan := Scan / 2;
         Result := Result + 1;
      end loop;
      return Result;
   end Highest_Bit;

   function Literal_Code (Length : Natural) return Natural is
   begin
      --  Codes 0 .. 15 are the lengths themselves; above that the baselines
      --  widen, so find the last code whose baseline Length still reaches.
      if Length <= 15 then
         return Length;
      end if;

      for Code in reverse 16 .. Max_Literal_Code loop
         if Length >= Literal_Baseline (Code) then
            return Code;
         end if;
      end loop;

      return 0;
   end Literal_Code;

   function Match_Code (Length : Natural) return Natural is
   begin
      if Length <= 34 then
         return Length - 3;
      end if;

      for Code in reverse 32 .. Max_Match_Code loop
         if Length >= Match_Baseline (Code) then
            return Code;
         end if;
      end loop;

      return 0;
   end Match_Code;

end Zlib.Zstd_Tables;
