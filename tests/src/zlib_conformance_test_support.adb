with Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;

package body Zlib_Conformance_Test_Support is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;

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

   procedure Assert_Bytes_Equal
     (Actual   : Zlib.Byte_Array;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & ": length mismatch");
      for I in Expected'Range loop
         Assert
           (Actual (Actual'First + (I - Expected'First)) = Expected (I),
            Message & ": byte mismatch");
      end loop;
   end Assert_Bytes_Equal;

   procedure Assert_One_Shot_OK
     (Input    : Zlib.Byte_Array;
      Header   : Zlib.Header_Type;
      Expected : Zlib.Byte_Array;
      Message  : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
   begin
      Assert (Status = Zlib.Ok, Message & ": one-shot status");
      Assert_Bytes_Equal (Output, Expected, Message & ": one-shot output");
   end Assert_One_Shot_OK;

   procedure Assert_One_Shot_Fails
     (Input   : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Message : String)
   is
      Status : Zlib.Status_Code;
      Output : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (Input, Header, Status);
      pragma Unreferenced (Output);
   begin
      Assert (Status /= Zlib.Ok, Message & ": one-shot must fail");
   end Assert_One_Shot_Fails;

   procedure Copy_Output
     (Out_Data : Ada.Streams.Stream_Element_Array;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Result   : in out Zlib.Byte_Array;
      Last     : in out Natural;
      Message  : String)
   is
   begin
      if Out_Last = Before_First (Out_Data) then
         return;
      end if;

      Assert
        (Out_Last >= Out_Data'First and then Out_Last <= Out_Data'Last,
         Message & ": Out_Last outside output buffer");

      for I in Out_Data'First .. Out_Last loop
         Last := Last + 1;
         Assert (Last <= Result'Last, Message & ": produced too many bytes");
         Result (Last) := Zlib.Byte (Out_Data (I));
      end loop;
   end Copy_Output;

   procedure Assert_Streaming_OK
     (Input       : Zlib.Byte_Array;
      Header      : Zlib.Header_Type;
      Expected    : Zlib.Byte_Array;
      Chunk_Size  : Positive;
      Output_Size : Positive;
      Message     : String)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
      Result : Zlib.Byte_Array (1 .. Natural'Max (Expected'Length, 1));
      Last   : Natural := 0;
   begin
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

            Assert
              (In_Last = Before_First (In_Data)
               or else (In_Last >= In_Data'First and then In_Last <= In_Data'Last),
               Message & ": In_Last outside input buffer");
            Copy_Output (Out_Data, Out_Last, Result, Last, Message);

            if In_Last /= Before_First (In_Data) then
               Pos := Pos + Natural (In_Last - In_Data'First + 1);
            else
               Assert
                 (Out_Last /= Before_First (Out_Data),
                  Message & ": no streaming progress");
            end if;
         end;
      end loop;

      for Guard in 1 .. 10_000 loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Size));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate
              (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            Assert
              (In_Last = Before_First (Empty_In),
               Message & ": empty finish input consumed");
            Copy_Output (Out_Data, Out_Last, Result, Last, Message);
            exit when Zlib.Stream_End (Filter)
              and then Out_Last = Before_First (Out_Data);
         end;
      end loop;

      Assert (Zlib.Stream_End (Filter), Message & ": Stream_End");
      Zlib.Close (Filter);
      Assert (Last = Expected'Length, Message & ": streamed length");
      Assert_Bytes_Equal (Result (1 .. Last), Expected, Message & ": streamed output");
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Assert_Streaming_OK;

   procedure Expect_Streaming_Zlib_Error
     (Input   : Zlib.Byte_Array;
      Header  : Zlib.Header_Type;
      Message : String)
   is
      Filter : Zlib.Filter_Type;
      Pos    : Natural := Input'First;
      Raised : Boolean := False;
   begin
      Zlib.Inflate_Init (Filter, Header => Header);

      begin
         for Guard in 1 .. 10_000 loop
            declare
               Count : constant Natural :=
                 (if Pos <= Input'Last then Natural'Min (3, Input'Last - Pos + 1) else 0);
               In_Data : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Count));
               Out_Data : Ada.Streams.Stream_Element_Array (1 .. 8);
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
                 (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);

               if Count > 0 and then In_Last /= Before_First (In_Data) then
                  Pos := Pos + Natural (In_Last - In_Data'First + 1);
               end if;

               Assert
                 (not Zlib.Stream_End (Filter),
                  Message & ": malformed stream must not reach Stream_End");

               Assert
                 (Count > 0
                  or else Out_Last /= Before_First (Out_Data),
                  Message & ": malformed stream made no progress before error");
            end;
         end loop;
      exception
         when Zlib.Zlib_Error =>
            Raised := True;
      end;

      Zlib.Close (Filter, Ignore_Error => True);
      Assert (Raised, Message & ": streaming must raise Zlib_Error");
   end Expect_Streaming_Zlib_Error;
end Zlib_Conformance_Test_Support;
