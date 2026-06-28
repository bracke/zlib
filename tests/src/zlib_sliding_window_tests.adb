with Ada.Streams; use Ada.Streams;
with AUnit.Assertions; use AUnit.Assertions;
with Zlib.Sliding_Window;

package body Zlib_Sliding_Window_Tests is
   use type Zlib.Sliding_Window.Write_Status;

   overriding function Name
     (T : Test_Case)
      return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Zlib.Sliding_Window");
   end Name;

   procedure Drain_Some
     (W      : in out Zlib.Sliding_Window.Window;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
   is
   begin
      Zlib.Sliding_Window.Drain (W, Buffer, Last);
   end Drain_Some;

   procedure Drain_All
     (W : in out Zlib.Sliding_Window.Window)
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 64);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      loop
         Zlib.Sliding_Window.Drain (W, Buffer, Last);
         exit when Last < Buffer'First;
      end loop;
   end Drain_All;

   procedure Put_And_Drain
     (W : in out Zlib.Sliding_Window.Window;
      B : Ada.Streams.Stream_Element)
   is
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      Zlib.Sliding_Window.Put_Byte (W, B, Status);
      Assert (Status = Zlib.Sliding_Window.Ok, "Put_Byte must accept byte before draining");
      Drain_All (W);
   end Put_And_Drain;

   procedure Finish_Copy_With_Drain
     (W : in out Zlib.Sliding_Window.Window;
      Status : in out Zlib.Sliding_Window.Write_Status)
   is
   begin
      while Status = Zlib.Sliding_Window.Need_Output loop
         Drain_All (W);
         Zlib.Sliding_Window.Continue_Copy (W, Status);
      end loop;
   end Finish_Copy_With_Drain;

   procedure Test_Reset_Clears_Counts
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      Zlib.Sliding_Window.Put_Byte (W, 16#41#, Status);
      Assert (Status = Zlib.Sliding_Window.Ok, "initial Put_Byte must succeed");
      Zlib.Sliding_Window.Reset (W);
      Assert (Zlib.Sliding_Window.Total_Output (W) = 0, "Reset must clear total output");
      Assert (Zlib.Sliding_Window.Pending_Output (W) = 0, "Reset must clear pending output");
      Assert (not Zlib.Sliding_Window.Copy_Active (W), "Reset must clear active copy state");
   end Test_Reset_Clears_Counts;

   procedure Test_Put_Byte_Makes_Pending
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      Zlib.Sliding_Window.Put_Byte (W, 16#41#, Status);
      Assert (Status = Zlib.Sliding_Window.Ok, "Put_Byte must succeed on empty window");
      Assert (Zlib.Sliding_Window.Pending_Output (W) = 1, "Put_Byte must make one byte pending");
      Assert (Zlib.Sliding_Window.Total_Output (W) = 1, "Put_Byte must increment total output");
   end Test_Put_Byte_Makes_Pending;

   procedure Test_Drain_Writes_One_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Buffer : Ada.Streams.Stream_Element_Array (10 .. 12) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Sliding_Window.Put_Byte (W, 16#41#, Status);
      Drain_Some (W, Buffer, Last);
      Assert (Last = 10, "Drain must set Out_Last to the written lower-bound index");
      Assert (Buffer (10) = 16#41#, "Drain must copy the pending byte");
      Assert (Zlib.Sliding_Window.Pending_Output (W) = 0, "Drain must consume pending output");
   end Test_Drain_Writes_One_Byte;

   procedure Test_Drain_Respects_Small_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Small  : Ada.Streams.Stream_Element_Array (5 .. 5) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Sliding_Window.Put_Byte (W, 1, Status);
      Zlib.Sliding_Window.Put_Byte (W, 2, Status);
      Drain_Some (W, Small, Last);
      Assert (Last = 5, "small Drain must fill exactly one caller slot");
      Assert (Small (5) = 1, "small Drain must write first queued byte first");
      Assert (Zlib.Sliding_Window.Pending_Output (W) = 1, "small Drain must leave remaining bytes pending");
   end Test_Drain_Respects_Small_Buffer;

   procedure Test_Drain_Append_Preserves_Existing_Output
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset := Buffer'First - 1;
   begin
      Zlib.Sliding_Window.Put_Byte (W, 1, Status);
      Zlib.Sliding_Window.Put_Byte (W, 2, Status);
      Zlib.Sliding_Window.Drain_Append (W, Buffer, Last);

      Zlib.Sliding_Window.Put_Byte (W, 3, Status);
      Zlib.Sliding_Window.Put_Byte (W, 4, Status);
      Zlib.Sliding_Window.Drain_Append (W, Buffer, Last);

      Assert (Last = 4, "Drain_Append must advance beyond prior output");
      for I in Buffer'Range loop
         Assert
           (Buffer (I) = Ada.Streams.Stream_Element (I),
            "Drain_Append must not overwrite earlier drained bytes");
      end loop;
   end Test_Drain_Append_Preserves_Existing_Output;

   procedure Test_Drain_Null_Output_Produces_Nothing
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Empty  : Ada.Streams.Stream_Element_Array (1 .. 0);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Zlib.Sliding_Window.Put_Byte (W, 1, Status);
      Zlib.Sliding_Window.Drain (W, Empty, Last);
      Assert (Last = Empty'First, "null Drain must use the safe no-output marker");
      Assert (Zlib.Sliding_Window.Pending_Output (W) = 1, "null Drain must not consume pending bytes");
   end Test_Drain_Null_Output_Produces_Nothing;

   procedure Test_Total_Output_Increments
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      for I in 1 .. 4 loop
         Zlib.Sliding_Window.Put_Byte (W, Ada.Streams.Stream_Element (I), Status);
         Assert (Status = Zlib.Sliding_Window.Ok, "Put_Byte in small sequence must succeed");
      end loop;
      Assert (Zlib.Sliding_Window.Total_Output (W) = 4, "Total_Output must count every produced byte");
   end Test_Total_Output_Increments;

   procedure Test_Start_Copy_Rejects_Distance_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      Put_And_Drain (W, 16#41#);
      Zlib.Sliding_Window.Start_Copy (W, 3, 0, Status);
      Assert (Status = Zlib.Sliding_Window.Invalid_Distance, "distance 0 must be rejected");
   end Test_Start_Copy_Rejects_Distance_Zero;

   procedure Test_Start_Copy_Rejects_Distance_Too_Large
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      Put_And_Drain (W, 16#41#);
      Zlib.Sliding_Window.Start_Copy (W, 3, 2, Status);
      Assert (Status = Zlib.Sliding_Window.Invalid_Distance, "distance beyond produced history must be rejected");
   end Test_Start_Copy_Rejects_Distance_Too_Large;

   procedure Test_Start_Copy_Rejects_Length_Below_Three
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      Put_And_Drain (W, 16#41#);
      Zlib.Sliding_Window.Start_Copy (W, 2, 1, Status);
      Assert (Status = Zlib.Sliding_Window.Invalid_Length, "copy length below 3 must be rejected");
   end Test_Start_Copy_Rejects_Length_Below_Three;

   procedure Test_Start_Copy_Rejects_Length_Above_258
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
   begin
      Put_And_Drain (W, 16#41#);
      Zlib.Sliding_Window.Start_Copy (W, 259, 1, Status);
      Assert (Status = Zlib.Sliding_Window.Invalid_Length, "copy length above 258 must be rejected");
   end Test_Start_Copy_Rejects_Length_Above_258;

   procedure Test_Copy_Distance_One_Repeats_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Put_And_Drain (W, 16#61#);
      Zlib.Sliding_Window.Start_Copy (W, 3, 1, Status);
      Finish_Copy_With_Drain (W, Status);
      Assert (Status = Zlib.Sliding_Window.Ok, "distance-1 copy must complete");
      Drain_Some (W, Buffer, Last);
      Assert (Last = 3, "copy length 3 must produce three pending bytes");
      for I in 1 .. 3 loop
         Assert (Buffer (Ada.Streams.Stream_Element_Offset (I)) = 16#61#,
                  "distance-1 copy must repeat the prior byte");
      end loop;
   end Test_Copy_Distance_One_Repeats_Byte;

   procedure Test_Overlapping_Copy_Works
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 31) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Put_And_Drain (W, 16#61#);
      Zlib.Sliding_Window.Start_Copy (W, 31, 1, Status);
      Finish_Copy_With_Drain (W, Status);
      Drain_Some (W, Buffer, Last);
      Assert (Last = 31, "overlapping copy must produce requested length");
      for I in Buffer'Range loop
         Assert (Buffer (I) = 16#61#, "overlapping distance-1 copy must self-extend");
      end loop;
      Assert (Zlib.Sliding_Window.Total_Output (W) = 32, "seed plus copy must total 32 bytes");
   end Test_Overlapping_Copy_Works;

   procedure Test_Overlapping_Copy_Advances_Source
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 6) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Put_And_Drain (W, 16#61#);
      Put_And_Drain (W, 16#62#);

      Zlib.Sliding_Window.Start_Copy (W, 6, 2, Status);
      Finish_Copy_With_Drain (W, Status);
      Drain_Some (W, Buffer, Last);

      Assert (Status = Zlib.Sliding_Window.Ok, "distance-2 overlapping copy must complete");
      Assert (Last = 6, "distance-2 overlapping copy must produce six bytes");

      for I in Buffer'Range loop
         if I mod 2 = 1 then
            Assert (Buffer (I) = 16#61#, "odd copied positions must repeat the first source byte");
         else
            Assert (Buffer (I) = 16#62#, "even copied positions must repeat the second source byte");
         end if;
      end loop;
   end Test_Overlapping_Copy_Advances_Source;

   procedure Test_Copy_Can_Continue_After_Drain
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 64) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Put_And_Drain (W, 16#78#);
      Zlib.Sliding_Window.Start_Copy (W, 258, 1, Status);
      Assert (Status = Zlib.Sliding_Window.Need_Output, "long copy must pause when pending queue fills");
      Assert (Zlib.Sliding_Window.Copy_Active (W), "copy must remain active after output fills");
      Drain_Some (W, Buffer, Last);
      Assert (Last = 64, "first drain must release one pending chunk");
      Zlib.Sliding_Window.Continue_Copy (W, Status);
      Finish_Copy_With_Drain (W, Status);
      Assert (Status = Zlib.Sliding_Window.Ok, "copy must finish after repeated drains and continues");
      Assert (not Zlib.Sliding_Window.Copy_Active (W), "copy must not remain active after completion");
      Assert (Zlib.Sliding_Window.Total_Output (W) = 259, "seed plus 258-byte copy must be counted");
   end Test_Copy_Can_Continue_After_Drain;

   procedure Test_History_Wraps_After_32768_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W : Zlib.Sliding_Window.Window;
   begin
      for I in 1 .. 32_769 loop
         Put_And_Drain (W, Ada.Streams.Stream_Element (I mod 251));
      end loop;
      Assert (Zlib.Sliding_Window.Total_Output (W) = 32_769, "history wrap must not lose total-output accounting");
      Assert (Zlib.Sliding_Window.Pending_Output (W) = 0, "test helper must leave no pending output after wrap");
   end Test_History_Wraps_After_32768_Bytes;

   procedure Test_Distance_Can_Refer_To_Wrapped_History
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      W      : Zlib.Sliding_Window.Window;
      Status : Zlib.Sliding_Window.Write_Status;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 3) := [others => 0];
      Last   : Ada.Streams.Stream_Element_Offset;
      Expected : constant Ada.Streams.Stream_Element := Ada.Streams.Stream_Element (2 mod 251);
   begin
      for I in 1 .. 32_769 loop
         Put_And_Drain (W, Ada.Streams.Stream_Element (I mod 251));
      end loop;

      Zlib.Sliding_Window.Start_Copy (W, 3, 32_768, Status);
      Finish_Copy_With_Drain (W, Status);
      Assert (Status = Zlib.Sliding_Window.Ok, "maximum distance must be accepted while present in wrapped history");
      Drain_Some (W, Buffer, Last);
      Assert (Last = 3, "wrapped-history copy must produce three bytes");
      Assert (Buffer (1) = Expected, "distance 32768 must read the oldest byte still in the ring");
   end Test_Distance_Can_Refer_To_Wrapped_History;

   overriding procedure Register_Tests
     (T : in out Test_Case)
   is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine (T, Test_Reset_Clears_Counts'Access, "Reset clears total and pending output");
      Registration.Register_Routine (T, Test_Put_Byte_Makes_Pending'Access, "Put_Byte stores one pending byte");
      Registration.Register_Routine (T, Test_Drain_Writes_One_Byte'Access, "Drain writes one pending byte");
      Registration.Register_Routine (T, Test_Drain_Respects_Small_Buffer'Access, "Drain respects small output buffer");
      Registration.Register_Routine
        (T,
         Test_Drain_Append_Preserves_Existing_Output'Access,
         "Drain_Append preserves prior output");
      Registration.Register_Routine
        (T,
         Test_Drain_Null_Output_Produces_Nothing'Access,
         "Drain with null output produces nothing");
      Registration.Register_Routine (T, Test_Total_Output_Increments'Access, "Total_Output increments for Put_Byte");
      Registration.Register_Routine (T, Test_Start_Copy_Rejects_Distance_Zero'Access, "Start_Copy rejects distance 0");
      Registration.Register_Routine
        (T,
         Test_Start_Copy_Rejects_Distance_Too_Large'Access,
         "Start_Copy rejects distance greater than output");
      Registration.Register_Routine
        (T,
         Test_Start_Copy_Rejects_Length_Below_Three'Access,
         "Start_Copy rejects length below 3");
      Registration.Register_Routine
        (T,
         Test_Start_Copy_Rejects_Length_Above_258'Access,
         "Start_Copy rejects length above 258");
      Registration.Register_Routine (T, Test_Copy_Distance_One_Repeats_Byte'Access, "Copy distance 1 repeats byte");
      Registration.Register_Routine (T, Test_Overlapping_Copy_Works'Access, "Overlapping copy works");
      Registration.Register_Routine
        (T,
         Test_Overlapping_Copy_Advances_Source'Access,
         "Overlapping copy advances source");
      Registration.Register_Routine (T, Test_Copy_Can_Continue_After_Drain'Access, "Copy can continue after Drain");
      Registration.Register_Routine
        (T,
         Test_History_Wraps_After_32768_Bytes'Access,
         "History wraps after more than 32768 bytes");
      Registration.Register_Routine
        (T,
         Test_Distance_Can_Refer_To_Wrapped_History'Access,
         "Distance can refer to wrapped history");
   end Register_Tests;

end Zlib_Sliding_Window_Tests;
