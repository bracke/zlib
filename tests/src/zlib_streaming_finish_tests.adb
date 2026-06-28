with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib; use Zlib;

package body Zlib_Streaming_Finish_Tests is
   use type Ada.Streams.Stream_Element_Offset;

   Plain_Hello : constant Zlib.Byte_Array :=
     [1 => Zlib.Byte (Character'Pos ('h')),
      2 => Zlib.Byte (Character'Pos ('e')),
      3 => Zlib.Byte (Character'Pos ('l')),
      4 => Zlib.Byte (Character'Pos ('l')),
      5 => Zlib.Byte (Character'Pos ('o'))];

   GZip_Hello : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib streaming Finish semantics");
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

   procedure Fill_Stream
     (Input : Zlib.Byte_Array;
      First : Ada.Streams.Stream_Element_Offset;
      Data  : out Ada.Streams.Stream_Element_Array)
   is
      pragma Unreferenced (First);
   begin
      for I in Input'Range loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (I - Input'First)) :=
           Ada.Streams.Stream_Element (Input (I));
      end loop;
   end Fill_Stream;

   procedure Decode_All
     (Header : Zlib.Header_Type;
      Input  : Zlib.Byte_Array)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
   begin
      Zlib.Inflate_Init (Filter, Header);

      for Guard in 1 .. 10_000 loop
         declare
            Count : constant Natural :=
              (if Pos <= Input'Last then Natural'Min (3, Input'Last - Pos + 1) else 0);
            In_Data : Ada.Streams.Stream_Element_Array
              (10 .. 9 + Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array (20 .. 23);
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            if Count > 0 then
               for I in 0 .. Count - 1 loop
                  In_Data (10 + Ada.Streams.Stream_Element_Offset (I)) :=
                    Ada.Streams.Stream_Element (Input (Pos + I));
               end loop;
            end if;

            Zlib.Translate
              (Filter,
               In_Data,
               In_Last,
               Out_Data,
               Out_Last,
               (if Count = 0 then Zlib.Finish else Zlib.No_Flush));

            if Count > 0 and then In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;

            exit when Zlib.Stream_End (Filter);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), "Finish must reach validated stream end");
      Zlib.Close (Filter);
   end Decode_All;

   procedure Expect_Finish_Zlib_Error
     (Header : Zlib.Header_Type;
      Input  : Zlib.Byte_Array)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
      Raised : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter, Header);

      begin
         for Guard in 1 .. 10_000 loop
            declare
               Count : constant Natural :=
                 (if Pos <= Input'Last then Natural'Min (4, Input'Last - Pos + 1) else 0);
               In_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Count));
               Out_Data : Ada.Streams.Stream_Element_Array (1 .. 2);
               In_Last  : Ada.Streams.Stream_Element_Offset;
               Out_Last : Ada.Streams.Stream_Element_Offset;
            begin
               if Count > 0 then
                  for I in 0 .. Count - 1 loop
                     In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                       Ada.Streams.Stream_Element (Input (Pos + I));
                  end loop;
               end if;

               Zlib.Translate
                 (Filter,
                  In_Data,
                  In_Last,
                  Out_Data,
                  Out_Last,
                  (if Count = 0 then Zlib.Finish else Zlib.No_Flush));

               if Count > 0 and then In_Last /= Before_First (In_Data) then
                  Pos := Pos + Natural (In_Last - In_Data'First + 1);
               end if;
            end;
         end loop;
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Assert (Raised, "Finish on truncated/malformed stream must raise Zlib_Error");
      Assert (Zlib.Is_Open (Filter), "failed filter remains open until Close");
      Zlib.Close (Filter, Ignore_Error => True);
   end Expect_Finish_Zlib_Error;

   procedure Test_Translate_Finish_Complete_Zlib
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Input  : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Plain_Hello, Status);
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Decode_All (Zlib.Default, Input);
   end Test_Translate_Finish_Complete_Zlib;

   procedure Test_Translate_Finish_Complete_Gzip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Decode_All (Zlib.GZip, GZip_Hello);
   end Test_Translate_Finish_Complete_Gzip;

   procedure Test_Translate_Finish_Truncated_Zlib
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Full   : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Plain_Hello, Status);
      Input  : constant Zlib.Byte_Array := Full (Full'First .. Full'Last - 2);
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Expect_Finish_Zlib_Error (Zlib.Default, Input);
   end Test_Translate_Finish_Truncated_Zlib;

   procedure Test_Translate_Finish_Truncated_Gzip
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input : constant Zlib.Byte_Array := GZip_Hello (GZip_Hello'First .. GZip_Hello'Last - 2);
   begin
      Expect_Finish_Zlib_Error (Zlib.GZip, Input);
   end Test_Translate_Finish_Truncated_Gzip;

   procedure Test_Flush_No_Flush_Incomplete_Succeeds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 6);
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Inflate_Init (Filter);
      Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.No_Flush);
      Assert (Out_Last = 4, "No_Flush before stream end must produce no output marker");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Flush_No_Flush_Incomplete_Succeeds;

   procedure Test_Flush_Finish_Incomplete_Raises
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter   : Zlib.Filter_Type;
      Out_Data : Ada.Streams.Stream_Element_Array (5 .. 6);
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Raised   : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter);
      begin
         Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;
      Assert (Raised, "Flush Finish before stream end must raise Zlib_Error");
      Zlib.Close (Filter, Ignore_Error => True);
   end Test_Flush_Finish_Incomplete_Raises;

   procedure Test_Flush_Finish_After_Stream_End_Succeeds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Filter : Zlib.Filter_Type;
      Status : Zlib.Status_Code;
      Input  : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Plain_Hello, Status);
      Pos    : Natural := Input'First;
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Zlib.Inflate_Init (Filter);

      for Guard in 1 .. 10_000 loop
         declare
            Count : constant Natural :=
              (if Pos <= Input'Last then Natural'Min (8, Input'Last - Pos + 1) else 0);
            In_Data  : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            if Count > 0 then
               for I in 0 .. Count - 1 loop
                  In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                    Ada.Streams.Stream_Element (Input (Pos + I));
               end loop;
            end if;
            Zlib.Translate
              (Filter,
               In_Data,
               In_Last,
               Out_Data,
               Out_Last,
               (if Count = 0 or else Pos + Count - 1 >= Input'Last
                then Zlib.Finish
                else Zlib.No_Flush));
            if Count > 0 and then In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            end if;
            exit when Zlib.Stream_End (Filter);
         end;
      end loop;

      declare
         Out_Data : Ada.Streams.Stream_Element_Array (2 .. 3);
         Out_Last : Ada.Streams.Stream_Element_Offset;
      begin
         Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
      end;

      Zlib.Close (Filter);
   end Test_Flush_Finish_After_Stream_End_Succeeds;

   procedure Test_Stream_End_Zlib_Trailer_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : Zlib.Status_Code;
      Full   : constant Zlib.Byte_Array := Zlib.Deflate_Stored (Plain_Hello, Status);
      Compressed_Body   : constant Zlib.Byte_Array := Full (Full'First .. Full'Last - 4);
      Tail   : constant Zlib.Byte_Array := Full (Full'Last - 3 .. Full'Last);
      Filter : Zlib.Filter_Type;
      B      : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Compressed_Body'Length));
      Tbuf   : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Tail'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Assert (Status = Zlib.Ok, "test zlib stream must be generated successfully");
      Fill_Stream (Compressed_Body, 1, B);
      Fill_Stream (Tail, 1, Tbuf);
      Zlib.Inflate_Init (Filter);
      Zlib.Translate (Filter, B, In_Last, Out_Data, Out_Last);
      Assert (not Zlib.Stream_End (Filter), "zlib Stream_End must wait for Adler-32 validation");
      Zlib.Translate (Filter, Tbuf, In_Last, Out_Data, Out_Last, Zlib.Finish);
      Assert (Zlib.Stream_End (Filter), "zlib Stream_End must follow Adler-32 validation");
      Zlib.Close (Filter);
   end Test_Stream_End_Zlib_Trailer_Validation;

   procedure Test_Stream_End_Gzip_Trailer_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Compressed_Body   : constant Zlib.Byte_Array := GZip_Hello (GZip_Hello'First .. GZip_Hello'Last - 8);
      Tail   : constant Zlib.Byte_Array := GZip_Hello (GZip_Hello'Last - 7 .. GZip_Hello'Last);
      Filter : Zlib.Filter_Type;
      B      : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Compressed_Body'Length));
      Tbuf   : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Tail'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 16);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      Fill_Stream (Compressed_Body, 1, B);
      Fill_Stream (Tail, 1, Tbuf);
      Zlib.Inflate_Init (Filter, Zlib.GZip);
      Zlib.Translate (Filter, B, In_Last, Out_Data, Out_Last);
      Assert (not Zlib.Stream_End (Filter), "gzip Stream_End must wait for trailer validation");
      Zlib.Translate (Filter, Tbuf, In_Last, Out_Data, Out_Last, Zlib.Finish);
      Assert (Zlib.Stream_End (Filter), "gzip Stream_End must follow CRC32/ISIZE validation");
      Zlib.Close (Filter);
   end Test_Stream_End_Gzip_Trailer_Validation;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Translate_Finish_Complete_Zlib'Access,
                                     "Translate Finish on complete zlib stream succeeds");
      Registration.Register_Routine (T, Test_Translate_Finish_Complete_Gzip'Access,
                                     "Translate Finish on complete gzip stream succeeds");
      Registration.Register_Routine (T, Test_Translate_Finish_Truncated_Zlib'Access,
                                     "Translate Finish on truncated zlib raises Zlib_Error");
      Registration.Register_Routine (T, Test_Translate_Finish_Truncated_Gzip'Access,
                                     "Translate Finish on truncated gzip raises Zlib_Error");
      Registration.Register_Routine (T, Test_Flush_No_Flush_Incomplete_Succeeds'Access,
                                     "Flush No_Flush before stream end succeeds");
      Registration.Register_Routine (T, Test_Flush_Finish_Incomplete_Raises'Access,
                                     "Flush Finish before stream end raises Zlib_Error");
      Registration.Register_Routine (T, Test_Flush_Finish_After_Stream_End_Succeeds'Access,
                                     "Flush Finish after Stream_End succeeds");
      Registration.Register_Routine (T, Test_Stream_End_Zlib_Trailer_Validation'Access,
                                     "Stream_End waits for zlib Adler validation");
      Registration.Register_Routine (T, Test_Stream_End_Gzip_Trailer_Validation'Access,
                                     "Stream_End waits for gzip CRC/ISIZE validation");
   end Register_Tests;
end Zlib_Streaming_Finish_Tests;
