// Smart Arm Controller - ESP32 receiver
//
// This is the Bluetooth sketch that drove this arm, moved onto WiFi. The servo
// pins, the one-degree ramp and the two output corrections are unchanged; what
// went is BluetoothSerial, and what arrived is a socket the phone can hold open
// across the room.
//
// Two ways in, both carrying the same string, chosen in the app on the Arm
// screen:
//
//   HTTP    GET http://<esp32-ip>/servo?cmd=1,115;2,95;3,108;4,60;
//   Socket  one TCP connection to <esp32-ip>:3333, one command per line
//
// Each pair is "channel,angle", channels 1-based: 1 base, 2 shoulder, 3 elbow,
// 4 gripper. Channel 5 is the phone's mirrored claw, for a gripper on two
// opposed servos; this arm has one, so it is ignored. The old four-value line
// the Bluetooth build sent still works too - "115,95,108,60" - which makes the
// board testable from a terminal:
//
//   printf '1,115;2,95;3,108;4,60;\n' | nc <esp32-ip> 3333
//
// The socket answers "ok;" to every line, and that answer is not decoration. A
// write into a TCP socket whose peer has vanished *succeeds* - it lands in the
// kernel's send buffer and is retransmitted quietly for tens of seconds - so
// the phone would report a healthy link while the arm sat still. The reply, and
// the app's "?;" heartbeat, are the only evidence the connection still exists.
// Keep both.
//
// Board: any ESP32. Library: ESP32Servo (Library Manager).
// Serial monitor: 115200, not 9600 - tracking sends about twelve commands a
// second and printing each one at 9600 would stall the loop.

#include <WiFi.h>
#include <WebServer.h>
#include <ESP32Servo.h>

const char* WIFI_SSID = "your-network";
const char* WIFI_PASSWORD = "your-password";

#define SERVO_BASE      25
#define SERVO_SHOULDER  26
#define SERVO_ELBOW     27
#define SERVO_GRIPPER   33

const uint16_t STREAM_PORT = 3333;

// A client that has said nothing for this long is gone - its phone slept, its
// WiFi dropped, it walked out of the building. Drop it, or it holds the one
// slot and the next connection is never served.
const unsigned long CLIENT_IDLE_MS = 5000;

// One degree per tick, which is what makes the arm sweep instead of snap. The
// Bluetooth build spent this in delay(); here it is a timestamp, because a loop
// that blocks for 40 ms is a loop that is not reading the socket. Lower is
// faster and coarser.
const unsigned long STEP_EVERY_MS = 15;

Servo servoBase, servoShoulder, servoElbow, servoGripper;

// Index 0..3 = base, shoulder, elbow, gripper.
// `target` is where the phone wants the arm; `current` is where the ramp has
// got to. They start apart on purpose: the arm sweeps to its park pose on
// power-up rather than jumping there.
int target[4]  = {0, 60, 40, 50};
int current[4] = {180, 150, 140, 100};
const char* NAMES[4] = {"base", "shoulder", "elbow", "gripper"};

WebServer server(80);
WiFiServer stream(STREAM_PORT);
WiFiClient client;
String inbox;
unsigned long lastHeard = 0;
unsigned long lastStep = 0;

// The two corrections from the original sketch. The base runs backwards
// against its linkage, and the gripper's travel is half the servo's. If the arm
// moves the wrong way after a rebuild, this is the function to look at, not the
// app.
void writeServo(int i, int angle) {
  int out = angle;
  if (i == 0) out = 180 - angle;
  if (i == 3) out = 180 - (2 * angle);
  out = constrain(out, 0, 180);

  switch (i) {
    case 0: servoBase.write(out); break;
    case 1: servoShoulder.write(out); break;
    case 2: servoElbow.write(out); break;
    case 3: servoGripper.write(out); break;
  }
}

void printCommand(const char* via, const String& line) {
  Serial.print("[");
  Serial.print(via);
  Serial.print("] ");
  Serial.print(line);
  Serial.print("  ->  ");
  for (int i = 0; i < 4; i++) {
    Serial.print(NAMES[i]);
    Serial.print(" ");
    Serial.print(target[i]);
    Serial.print(i < 3 ? ", " : "\n");
  }
}

// Returns false for the app's heartbeat, which carries no angles and should not
// be printed twelve hundred times an hour.
bool applyCommand(const String& cmd) {
  String line = cmd;
  line.trim();
  if (line.length() == 0 || line == "?;" || line == "?") return false;

  if (line.indexOf(';') >= 0) {
    // "channel,angle;" pairs, the format the desktop script wrote to the serial
    // port and the app still sends.
    int len = line.length();
    int start = 0;
    int applied = 0;

    while (start < len) {
      int end = line.indexOf(';', start);
      if (end == -1) break;

      String pair = line.substring(start, end);
      start = end + 1;

      int comma = pair.indexOf(',');
      if (comma == -1) continue;

      int channel = pair.substring(0, comma).toInt();
      int angle = pair.substring(comma + 1).toInt();
      if (channel < 1 || channel > 4) continue;   // 5 is the mirrored claw
      target[channel - 1] = constrain(angle, 0, 180);
      applied++;
    }
    return applied > 0;   // a line of nothing but channel 5 is not a command
  }

  // The Bluetooth build's line: "base,shoulder,elbow,gripper".
  int v[4];
  if (sscanf(line.c_str(), "%d,%d,%d,%d", &v[0], &v[1], &v[2], &v[3]) == 4) {
    for (int i = 0; i < 4; i++) target[i] = constrain(v[i], 0, 180);
    return true;
  }
  return false;
}

// One degree per servo per tick, toward the target. Nothing here blocks.
void stepServos() {
  if (millis() - lastStep < STEP_EVERY_MS) return;
  lastStep = millis();

  for (int i = 0; i < 4; i++) {
    if (current[i] == target[i]) continue;
    current[i] += (target[i] > current[i]) ? 1 : -1;
    writeServo(i, current[i]);
  }
}

void handleServo() {
  if (!server.hasArg("cmd")) {
    server.send(400, "text/plain", "missing cmd");
    return;
  }
  String cmd = server.arg("cmd");
  if (applyCommand(cmd)) printCommand("http", cmd);
  server.send(200, "text/plain", "ok");
}

void handleRoot() {
  String body = "Smart Arm receiver\n\n";
  for (int i = 0; i < 4; i++) {
    body += String(NAMES[i]) + ": at " + String(current[i]) +
            ", going to " + String(target[i]) + "\n";
  }
  body += "\nstream port " + String(STREAM_PORT);
  body += (client && client.connected()) ? " (client connected)\n" : " (idle)\n";
  server.send(200, "text/plain", body);
}

void pumpStream() {
  // Newest connection wins. The old one is either dead or a phone that
  // reconnected without closing cleanly, and only one can drive the arm.
  WiFiClient waiting = stream.available();
  if (waiting) {
    if (client) client.stop();
    client = waiting;
    client.setNoDelay(true);
    inbox = "";
    lastHeard = millis();
    Serial.print("[socket] client ");
    Serial.println(client.remoteIP());
  }

  if (!client) return;
  if (!client.connected()) {
    client.stop();
    Serial.println("[socket] client gone");
    return;
  }

  while (client.available()) {
    char c = client.read();
    lastHeard = millis();

    if (c == '\n') {
      if (applyCommand(inbox)) printCommand("socket", inbox);
      client.print("ok;\n");   // proof of life - see the note at the top
      inbox = "";
    } else if (c != '\r') {
      // TCP is a stream of bytes, not of messages: a command can arrive split
      // across packets, and two can arrive in one read. The newline is the
      // frame, and nothing may be applied before one turns up.
      if (inbox.length() < 64) inbox += c;
      else inbox = "";         // nonsense on the wire; resync at the newline
    }
  }

  if (millis() - lastHeard > CLIENT_IDLE_MS) {
    Serial.println("[socket] client idle, dropping");
    client.stop();
  }
}

void setup() {
  Serial.begin(115200);

  servoBase.attach(SERVO_BASE);
  servoShoulder.attach(SERVO_SHOULDER);
  servoElbow.attach(SERVO_ELBOW);
  servoGripper.attach(SERVO_GRIPPER);
  for (int i = 0; i < 4; i++) writeServo(i, current[i]);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print(".");
  }

  Serial.println();
  Serial.print("ready at http://");
  Serial.print(WiFi.localIP());        // <- type this into the app's Arm screen
  Serial.print("  and socket ");
  Serial.print(WiFi.localIP());
  Serial.print(":");
  Serial.println(STREAM_PORT);

  server.on("/", handleRoot);
  server.on("/servo", handleServo);
  server.begin();

  stream.begin();
  stream.setNoDelay(true);

  lastStep = millis();
  lastHeard = millis();
}

void loop() {
  server.handleClient();
  pumpStream();
  stepServos();
}
