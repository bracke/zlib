package body Zlib.LZ77_Matcher.Testing is

   procedure Arm (Fail_At : Natural := 0) is
   begin
      Probe :=
        (Armed       => True,
         Fail_At     => Fail_At,
         Attempted   => 0,
         Outstanding => 0);
   end Arm;

   procedure Disarm is
   begin
      Probe := (others => <>);
   end Disarm;

   function Attempted return Natural is
   begin
      return Probe.Attempted;
   end Attempted;

   function Outstanding return Integer is
   begin
      return Probe.Outstanding;
   end Outstanding;

end Zlib.LZ77_Matcher.Testing;
