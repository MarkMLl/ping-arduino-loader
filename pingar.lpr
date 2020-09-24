program pingar;

(* Investigate whether an Arduino loader responds to a query on the indicated   *)
(* port, sequencing through a number of speeds. See AVR Application Note 061.   *)
(*                                                              MarkMLl         *)

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes
  { you can add units after this } , SysUtils, Serial, termio;

const
  topSpeedIndex= (* 10 *) 5;
  dummySpeedIndex= topSpeedIndex + 1; (* Dummy required for end-of-loop comparison *)

type
  tSpeedIndices= 0..dummySpeedIndex;

var
  speeds: array[tSpeedIndices] of integer= (115200, (* 74880, *) 57600, 38400, 19200,
                                9600 (*, 2000000, 1000000, 500000, 250000 *), 230400, 0);

// TODO : Extra speeds above are as supported by the Arduino IDE.
// Do not enable extra speeds without checking for support in bpsAsInt() below.

(* Note on the above. An Arduino Uno or Mega etc. connected via USB will        *)
(* probably respond at 115k, and not at other speeds. A more recent variant     *)
(* further removed from the original FTDI lineage might repond at other speeds. *)
(* Targets such as the Blue Pill, ESP32, Teensy and so on might or might not    *)
(* use a compatible loader: compatibility of the protocol obviously takes       *)
(* precedence over accuracy of serial speed (BPS, popularly referred to as      *)
(* Baud).                                                                       *)
(*                                                                              *)
(* If the loader on the Arduino is compiled for the wrong clock speed then the  *)
(* serial speed will be completely adrift. If the Arduino uses a ceramic        *)
(* resonator rather than a crystal then its serial speed might be outside the   *)
(* roughly 10% variation that a host computer will tolerate. Since this program *)
(* doesn't microstep through several orders of magnitude there are limits to    *)
(* what it can interwork with.                                                  *)

label
  noParams;

var
  portName, lockfile: string;
  handle: TSerialHandle;
  state: TSerialState;
  i: tSpeedIndices;


(* This is for use during testing: shuffle the speed order so that we can see
  that neither the Arduino nor this program is being screwed by trying to talk
  at the wrong speed.
*)
procedure shuffleSpeeds;

var
  i: integer;
  j, k: tSpeedIndices;
  speed: integer;

begin
  Randomize;
  for i := 0 to 31 do begin
    j := Random(Ord(topSpeedIndex) + 1);
    k := Random(Ord(topSpeedIndex) + 1);
    speed := speeds[j];
    speeds[j] := speeds[k];
    speeds[k] := speed
  end
end { shuffleSpeeds } ;


(* This is an accurate inverse of what SerSetParams does.
*)
function bpsAsInt(tios: termios): integer;

// TODO : Explore OS-specific facilities for speeds used by Arduinos which are non-standard to Linux etc.

begin
  case tios.c_cflag and CBAUD of
    B50:     result := 50;
    B75:     result := 75;
    B110:    result := 110;
    B134:    result := 134;
    B150:    result := 150;
    B200:    result := 200;
    B300:    result := 300;
    B600:    result := 600;
    B1200:   result := 1200;
    B1800:   result := 1800;
    B2400:   result := 2400;
    B4800:   result := 4800;
    B19200:  result := 19200;
    B38400:  result := 38400;
    B57600:  result := 57600;
    B115200: result := 115200;
    B230400: result := 230400
{$ifndef BSD}
    ; B460800: result := 460800
{$endif}
  otherwise
    result := 9600
  end
end { bpsAsInt } ;


(* Return true if there's an arduino at the other end, else false.
*)
function exercise(handle: TSerialHandle; normal: boolean): boolean;

const
  verbose= false;
  longDelay= 500;                       (* Uno: 0..10,000 mSec, i.e. non-critical *)
  shortDelay= 975;                      (* Uno: 70..1,400 mSec                  *)
  timeout= 750;                         (* Normally < 1,000 mSec                *)

var
  qry: ansistring= #$30 + #$20;
  rsp: array[0..1] of byte;
  bytes: integer;

begin
  result := false;

(* The precise significance of "charge" and "discharge" here depends on the     *)
(* polarity of the DTR signal (i.e. whether there's an invertor or transistor   *)
(* on the board) and on how the capacitor is wired, i.e. between DTR and Vcc    *)
(* (+ve) or between DTR and 0v.                                                 *)

  try
    Sleep(longDelay);
    SerSetDtr(handle, not normal);
    SerSetRts(handle, not normal);
    Sleep(shortDelay);                  (* Capacitor charge time?               *)

(* A normal Arduino comes out of reset when DTR goes active. Note that this     *)
(* might put rubbish on the serial line, the position of SerFlushInput() is     *)
(* critical.                                                                    *)

    SerSetDtr(handle, normal);
    SerSetRts(handle, normal);
    if normal then
      Write('with DTR+RTS active... ')
    else
      Write('with DTR+RTS inactive... ');

(* Minimum delay here is the time it takes the capacitor to discharge. Maximum  *)
(* is that plus the loader timeout, which is usually 1 second.                  *)

    Sleep(shortDelay);                  (* Must be less than watchdog timeout   *)
    SerFlushInput(handle);
    SerWrite(handle, qry[1], Length(qry));
    if verbose then
      Write('written ', Length(qry), ' bytes... ');
    FillByte(rsp, 2, 0);
    bytes := SerReadTimeout(handle, rsp, SizeOf(rsp), timeout);
    if verbose then
      Write('read ', bytes, ' bytes... ');
    if (bytes = SizeOf(rsp)) and (rsp[0] = $14) and (rsp[1] = $10) then
      exit(true)
  finally
    if result or not normal then
      WriteLn
  end;

(* In general, it is probably safest to assume that we have spent so much time  *)
(* waiting for a response in this function that the loader's watchdog has reset *)
(* the chip. The implication of this is that a subsequent attempt to e.g. read  *)
(* the chip signature will have to start over with another chip reset, but at   *)
(* least by now we should know which polarity to use.                           *)
(*                                                                              *)
(* In practice, AvrDude handles signatures entirely adequately, so let's stick  *)
(* to the speed and polarity detection which it doesn't attempt.                *)

  SerSetDtr(handle, true);
  SerSetRts(handle, true)
end { exercise } ;


begin
//  shuffleSpeeds;                        (* Used during debugging only           *)
  case ParamCount() of
    0: begin
noParams:
         WriteLn();
         WriteLn('Usage: pingar PORT');
         WriteLn();
         WriteLn('Look for an Arduino loader, working through all plausible speeds.');
         WriteLn();
         exit
       end;
    1: begin
         if Pos('-', ParamStr(1)) = 1 then (* -help, --help, --version etc.     *)
           goto noParams;
         if Pos('/?', ParamStr(1)) = 1 then
           goto noParams;
         portname := ParamStr(1);
         lockfile := portname;
         Delete(lockfile, 1, Length('/dev/'));
         lockfile := '/run/lock/LCK..' + lockfile
       end
  otherwise
    goto noParams
  end;

(* We have a viable port name, note that I'm making no attempt to synthesise a  *)
(* list of possible names since there's no GUI and the possibilities (i.e. it   *)
(* will probably look like a serial port but could be from any manufacturer)    *)
(* are too diverse.                                                             *)

  if FileExists(lockfile) then
    WriteLn(StdErr, 'WARNING: Lockfile ', lockfile, ' exists, expect problems.');
  handle := SerOpen(portname);
  if handle <= 0 then
    WriteLn(StdErr, 'ERROR: cannot open ', portname)
  else
    try
      i := 0;
      while i <= topSpeedIndex do begin // Note definition of dummy value at top
        if speeds[i] <> 0 then begin
          Write('Setting port to ', speeds[i], ' BPS... ');
// TODO : Explore OS-specific facilities for speeds used by Arduinos which are non-standard to Linux etc.
          SerSetParams(handle, speeds[i], 8, NoneParity, 2, []);
          state := SerSaveState(handle);
          if not bpsAsInt(state.tios) = speeds[i] then
            WriteLn('failed, got ', bpsAsInt(state.tios))
          else begin
            Write('exercising connection... ');
            if exercise(handle, true) then
              break;
            if exercise(handle, false) then
              break
          end
        end;
        i += 1
      end;
      if i <= topSpeedIndex then
        WriteLn('Arduino loader responded at ', speeds[i], ' BPS')
      else
        WriteLn('No Arduino loader response')
    finally
      SerClose(handle)
    end
end.

