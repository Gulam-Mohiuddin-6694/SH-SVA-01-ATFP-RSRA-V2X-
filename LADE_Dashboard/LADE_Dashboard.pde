import processing.serial.*;
import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// --- CRITICAL CONFIGURATION ---
String SERIAL_PORT = "COM22"; // UPDATE THIS TO MATCH YOUR ESP32 GATEWAY COM PORT!
int BAUD_RATE = 115200;

// --- STATE VARIABLES ---
Serial serialPort;
boolean simulationMode = true;
long lastLiveDataTime = 0;
int currentTab = 0; // 0: Dashboard, 1: EMS/Weather, 2: V2X Logs

// Application State
String currentDetection = "NORMAL TRAFFIC";
float targetConfidence = 0.95;
float displayConfidence = 0.0; // For smooth gauge animation
color currentColor, targetColor; // Smooth color transitions

// Environment State
String weatherCondition = "CLEAR"; 
int lastWeatherChange = 0;

// Traffic Light State
int trafficLightStatus = 0; // 0: Green, 1: Yellow, 2: Red
float redAlpha = 0, yellowAlpha = 0, greenAlpha = 0; // Smooth light glow
String signalTimingText = "";

// L.A.D.E. (Logic Augmented Decision Engine) Outputs
String decisionAction = "";
String policyConstraint = "";
String explainability = "";

// Logs
ArrayList<LogEntry> v2xLogs = new ArrayList<LogEntry>();
ArrayList<LogEntry> emergencyLogs = new ArrayList<LogEntry>();

// --- PREMIUM LIGHT THEME (Tailwind UI Inspired) ---
color bgApp = color(241, 245, 249);       // Slate 50
color bgSidebar = color(255, 255, 255);   // White
color bgCard = color(255, 255, 255);      // White
color textPrimary = color(15, 23, 42);    // Slate 900
color textSecondary = color(100, 116, 139);// Slate 500
color borderLight = color(226, 232, 240); // Slate 200
color accentPrimary = color(59, 130, 246); // Blue 500
color accentLight = color(219, 234, 254);  // Blue 100

// Dynamic Classification Colors
color cGreen = color(16, 185, 129);  // Normal
color cAmber = color(245, 158, 11);  // Heavy / Construction
color cRed = color(239, 68, 68);     // Accident / Protestors
color cPurple = color(139, 92, 246); // Pedestrian
color cBlue = color(14, 165, 233);   // Ambulance

PFont fontTitle, fontBold, fontSemiBold, fontRegular, fontMono, fontSmall;

class LogEntry {
  String timestamp;
  String message;
  color typeColor;
  LogEntry(String t, String m, color c) { timestamp = t; message = m; typeColor = c; }
}

void setup() {
  size(1440, 900, P2D);
  smooth(8); // Maximum anti-aliasing for premium look
  
  // High-Quality Typography
  fontTitle = createFont("SansSerif", 32, true);
  fontBold = createFont("SansSerif-Bold", 24, true);
  fontSemiBold = createFont("SansSerif-Bold", 16, true);
  fontRegular = createFont("SansSerif", 15, true);
  fontSmall = createFont("SansSerif", 12, true);
  fontMono = createFont("Monospaced", 13, true);
  
  currentColor = cGreen;
  targetColor = cGreen;
  
  // Setup Serial Connection
  try {
    serialPort = new Serial(this, SERIAL_PORT, BAUD_RATE);
    serialPort.bufferUntil('\n');
    logV2X("[SYS] Gateway Connected on " + SERIAL_PORT, cGreen);
    simulationMode = false;
    lastLiveDataTime = millis();
  } catch (Exception e) {
    simulationMode = true;
    logV2X("[WARN] Serial Port " + SERIAL_PORT + " unavailable.", cAmber);
    logV2X("[SYS] Engine fallback to Simulation Mode.", accentPrimary);
  }
  
  logEmergency("[SYS] Multi-Agency Dispatch Node Online (100, 104, 108).", accentPrimary);
  updateDecisionEngine("NORMAL TRAFFIC", 0.98);
}

void draw() {
  background(bgApp);
  
  // Auto-switch to simulation if no live data for 15 seconds
  if (!simulationMode && (millis() - lastLiveDataTime > 15000)) {
    simulationMode = true;
    logV2X("[WARN] Live stream timeout. Reverting to Agentic Simulation.", cRed);
  }
  
  // Weather Simulation Logic (Rotates periodically)
  if (millis() - lastWeatherChange > 25000) {
    cycleWeather();
    lastWeatherChange = millis();
    updateDecisionEngine(currentDetection, targetConfidence); // Re-evaluate with new weather
  }
  
  // Simulation Data Generation
  if (simulationMode && frameCount % 360 == 0) { // Every ~6 seconds
    simulateIncomingData();
  }
  
  // Smooth Animations (Lerping)
  displayConfidence = lerp(displayConfidence, targetConfidence, 0.05);
  currentColor = lerpColor(currentColor, targetColor, 0.05);
  
  // Traffic Light Glow Animations
  redAlpha = lerp(redAlpha, trafficLightStatus == 2 ? 255 : 40, 0.1);
  yellowAlpha = lerp(yellowAlpha, trafficLightStatus == 1 ? 255 : 40, 0.1);
  greenAlpha = lerp(greenAlpha, trafficLightStatus == 0 ? 255 : 40, 0.1);
  
  drawSidebar();
  drawTopHeader();
  
  // Multi-Screen Content Area
  pushMatrix();
  translate(280, 80); 
  switch(currentTab) {
    case 0: drawDashboardTab(); break;
    case 1: drawEnvironmentEMSTab(); break;
    case 2: drawV2XLogTab(); break;
  }
  popMatrix();
}

void drawSidebar() {
  // Sidebar shadow
  fill(0, 0, 0, 8);
  noStroke();
  rect(280, 0, 10, height);
  
  // Sidebar Base
  fill(bgSidebar);
  rect(0, 0, 280, height);
  
  // Logo Area
  fill(textPrimary);
  textFont(fontBold);
  textAlign(LEFT, TOP);
  text("L.A.D.E.", 30, 30);
  
  fill(accentPrimary);
  textFont(fontSmall);
  text("V2X AGENTIC GATEWAY", 30, 60);
  
  stroke(borderLight);
  strokeWeight(1);
  line(0, 90, 280, 90);
  
  // Nav Items
  drawNavItem("Agentic Dashboard", 110, 0);
  drawNavItem("Multi-Modal & EMS", 170, 1);
  drawNavItem("V2X Mesh Telemetry", 230, 2);
  
  // Connection Status (Bottom)
  drawStatusPill();
}

void drawNavItem(String label, int y, int tabId) {
  boolean active = (currentTab == tabId);
  noStroke();
  if (active) {
    fill(accentLight);
    rect(15, y, 250, 45, 8);
    fill(accentPrimary);
    rect(15, y+10, 4, 25, 4);
  }
  
  fill(active ? accentPrimary : textSecondary);
  textFont(fontSemiBold);
  textAlign(LEFT, CENTER);
  text(label, 40, y + 21);
  
  // Hover & Click Logic
  if (mouseX > 15 && mouseX < 265 && mouseY > y && mouseY < y + 45) {
    if (!active) { fill(0,0,0,10); rect(15, y, 250, 45, 8); }
    if (mousePressed) currentTab = tabId;
  }
}

void drawStatusPill() {
  int by = height - 80;
  stroke(borderLight);
  fill(bgApp);
  rect(20, by, 240, 56, 12);
  
  noStroke();
  fill(simulationMode ? cAmber : cGreen);
  ellipse(45, by + 28, 12, 12);
  
  fill(textPrimary);
  textFont(fontSemiBold);
  textAlign(LEFT, CENTER);
  text(simulationMode ? "SIMULATION MODE" : "LIVE SENSOR ACTIVE", 65, by + 20);
  
  fill(textSecondary);
  textFont(fontSmall);
  text(simulationMode ? "Awaiting COM Data" : "Port: " + SERIAL_PORT, 65, by + 38);
}

void drawTopHeader() {
  fill(bgSidebar);
  noStroke();
  rect(280, 0, width - 280, 80);
  
  stroke(borderLight);
  line(280, 80, width, 80);
  
  fill(textPrimary);
  textFont(fontBold);
  textAlign(LEFT, CENTER);
  String[] titles = {"Traffic Optimization Overview", "Environment & Emergency Dispatch", "Raw V2X Communication Stream"};
  text(titles[currentTab], 320, 40);
  
  // Clock / Time
  fill(textSecondary);
  textFont(fontRegular);
  textAlign(RIGHT, CENTER);
  String t = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
  text("System Time: " + t, width - 40, 40);
}

void drawCard(float x, float y, float w, float h, String title) {
  // Ultra-smooth shadow emulation
  noStroke();
  fill(0, 0, 0, 3);
  rect(x+4, y+8, w, h, 16);
  fill(0, 0, 0, 4);
  rect(x+2, y+4, w, h, 16);
  fill(0, 0, 0, 5);
  rect(x+1, y+2, w, h, 16);
  
  // Card Body
  fill(bgCard);
  stroke(borderLight);
  strokeWeight(1);
  rect(x, y, w, h, 16);
  
  // Card Title
  fill(textSecondary);
  textFont(fontSemiBold);
  textAlign(LEFT, TOP);
  text(title.toUpperCase(), x + 25, y + 20);
  
  stroke(borderLight);
  line(x + 20, y + 45, x + w - 20, y + 45);
}

void drawDashboardTab() {
  // Top Row
  drawCard(40, 30, 600, 320, "V2X COMPUTER VISION CLASSIFICATION");
  drawClassificationContent(40, 30);
  
  drawCard(670, 30, 450, 320, "MULTI-MODAL SIGNAL CONTROLLER");
  drawTrafficLightContent(670, 30);
  
  // Bottom Row
  drawCard(40, 380, 1080, 400, "LOGIC AUGMENTED DECISION ENGINE (L.A.D.E.)");
  drawLADEContent(40, 380);
}

void drawClassificationContent(float cx, float cy) {
  // Left: Label
  textAlign(LEFT, TOP);
  fill(currentColor);
  textFont(fontTitle);
  text(currentDetection, cx + 25, cy + 90);
  
  fill(textSecondary);
  textFont(fontRegular);
  text("Latest telemetry processed via edge-node mesh.", cx + 25, cy + 140);
  
  // Right: Premium Arc Gauge
  float gx = cx + 450;
  float gy = cy + 220;
  float r = 100;
  
  noFill();
  strokeCap(ROUND);
  strokeWeight(16);
  stroke(borderLight);
  arc(gx, gy, r*2, r*2, -PI, 0);
  
  stroke(currentColor);
  float endAngle = map(displayConfidence, 0, 1, -PI, 0);
  arc(gx, gy, r*2, r*2, -PI, endAngle);
  
  fill(textPrimary);
  textAlign(CENTER, CENTER);
  textFont(fontBold);
  textSize(36);
  text(nf(displayConfidence * 100, 0, 1) + "%", gx, gy - 30);
  
  fill(textSecondary);
  textFont(fontSmall);
  text("AI CONFIDENCE", gx, gy + 10);
}

void drawTrafficLightContent(float cx, float cy) {
  float lx = cx + 50;
  float ly = cy + 70;
  
  // Modern Traffic Light Housing
  fill(30, 41, 59);
  noStroke();
  rect(lx, ly, 90, 220, 24);
  
  // Lights with glowing lerp values
  drawModernLight(lx + 45, ly + 45, cRed, redAlpha);
  drawModernLight(lx + 45, ly + 110, cAmber, yellowAlpha);
  drawModernLight(lx + 45, ly + 175, cGreen, greenAlpha);
  
  // Text Specs
  textAlign(LEFT, TOP);
  fill(textSecondary);
  textFont(fontSemiBold);
  text("ACTIVE PHASE PROTOCOL", lx + 120, ly + 10);
  
  fill(textPrimary);
  textFont(fontRegular);
  text(signalTimingText, lx + 120, ly + 40, 250, 150);
}

void drawModernLight(float x, float y, color c, float alpha) {
  noStroke();
  // Outer Glow
  if (alpha > 50) {
    fill(red(c), green(c), blue(c), alpha * 0.2);
    ellipse(x, y, 70, 70);
  }
  // Core Light
  fill(red(c), green(c), blue(c), alpha);
  ellipse(x, y, 40, 40);
  
  // Inner Brightness reflection
  if (alpha > 200) {
    fill(255, 255, 255, 100);
    ellipse(x - 5, y - 5, 15, 15);
  }
}

void drawLADEContent(float cx, float cy) {
  float startY = cy + 80;
  
  // Action Banner (Dynamically colored)
  fill(red(currentColor), green(currentColor), blue(currentColor), 15);
  stroke(currentColor);
  strokeWeight(2);
  rect(cx + 30, startY, 1020, 90, 12);
  
  fill(currentColor);
  textFont(fontSemiBold);
  textAlign(LEFT, TOP);
  text("EXECUTED AGENTIC ACTION", cx + 50, startY + 15);
  
  fill(textPrimary);
  textFont(fontRegular);
  text(decisionAction, cx + 50, startY + 45, 980, 50);
  
  // Split Panels for Policy & Explainability
  startY += 120;
  noStroke();
  
  // Policy Box
  fill(248, 250, 252); // Slate 50
  stroke(borderLight);
  strokeWeight(1);
  rect(cx + 30, startY, 495, 160, 12);
  
  fill(textPrimary);
  textFont(fontSemiBold);
  text("POLICY CONSTRAINT GOVERNING DECISION", cx + 50, startY + 20);
  fill(textSecondary);
  textFont(fontRegular);
  text(policyConstraint, cx + 50, startY + 55, 450, 100);
  
  // Explainability Box
  fill(248, 250, 252);
  stroke(borderLight);
  rect(cx + 555, startY, 495, 160, 12);
  
  fill(textPrimary);
  textFont(fontSemiBold);
  text("EXPLAINABLE AI CONTEXT (NARRATIVE)", cx + 575, startY + 20);
  fill(textSecondary);
  textFont(fontRegular);
  text(explainability, cx + 575, startY + 55, 450, 100);
}

void drawEnvironmentEMSTab() {
  drawCard(40, 30, 450, 200, "METEOROLOGICAL EDGE SENSOR");
  
  fill(accentPrimary);
  textFont(fontTitle);
  textAlign(LEFT, TOP);
  text(weatherCondition + " CONDITIONS", 65, 90);
  fill(textSecondary);
  textFont(fontRegular);
  String wText = weatherCondition.equals("CLEAR") ? "Optimal traction. Standard policies apply." : 
                 weatherCondition.equals("RAIN") ? "Friction reduced. Safety buffer extended +2s." :
                 "Visibility reduced. V2X warning beacons transmitting.";
  text("Impact: " + wText, 65, 140, 400, 80);
  
  drawCard(520, 30, 600, 750, "MULTI-AGENCY DISPATCH (EMS / POLICE)");
  drawStyledLog(520, 30, emergencyLogs, 600, 750);
}

void drawV2XLogTab() {
  drawCard(40, 30, 1080, 750, "RAW V2X MESH NETWORK TELEMETRY (RX/TX)");
  drawStyledLog(40, 30, v2xLogs, 1080, 750);
}

void drawStyledLog(float cx, float cy, ArrayList<LogEntry> logs, float w, float h) {
  textFont(fontMono);
  textAlign(LEFT, TOP);
  int yOffset = (int)cy + 70;
  int maxLines = (int)((h - 100) / 28); // Line height
  
  // Draw subtle alternating background lines
  noStroke();
  for(int i=0; i<maxLines; i++) {
    if(i%2==0) { fill(248, 250, 252); rect(cx+2, yOffset + (i*28) - 5, w-4, 28); }
  }
  
  for (int i = max(0, logs.size() - maxLines); i < logs.size(); i++) {
    LogEntry log = logs.get(i);
    fill(log.typeColor);
    text("[" + log.timestamp + "]", cx + 30, yOffset);
    fill(textPrimary);
    text(log.message, cx + 130, yOffset);
    yOffset += 28;
  }
}

void updateDecisionEngine(String state, float conf) {
  String timestamp = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
  
  // Modifiers based on weather
  String weatherMod = "";
  int yellowMod = 0;
  if (weatherCondition.equals("RAIN")) { weatherMod = " [Weather Adjust: +2s Clearance]"; yellowMod = 2; }
  
  // 1. NORMAL TRAFFIC
  if (state.equals("NORMAL TRAFFIC")) {
    targetColor = cGreen; trafficLightStatus = 0; 
    signalTimingText = "Standard Throughput\nCycle: Green 45s, Yellow " + (5+yellowMod) + "s, Red 30s.";
    decisionAction = "[STANDBY] Flow optimal. Base timing active." + weatherMod;
    policyConstraint = "P-1.0: Maintain baseline vehicle throughput. Avoid unnecessary interruption to primary artery.";
    explainability = "CV engine identifies standard vehicle clustering. No anomalies detected within junction bounding box. Multi-modal queues are nominal.";
  } 
  // 2. HEAVY TRAFFIC
  else if (state.equals("HEAVY TRAFFIC")) {
    targetColor = cAmber; trafficLightStatus = 0; 
    signalTimingText = "Extended Main Phase\nCycle: Green 70s, Yellow " + (5+yellowMod) + "s, Red 20s.";
    decisionAction = "[INTERVENTION] Increasing Main green phase. V2X APIs rerouting incoming mesh vehicles." + weatherMod;
    policyConstraint = "P-2.4: Prevent gridlock spillover into adjacent intersections by prioritizing saturated approaches.";
    explainability = "Spillover prediction triggered. Congestion buildup detected beyond 50m radius. Prolonging throughput to clear upstream nodes.";
    logV2X("[TX] BROADCAST: API_REROUTE_SUGGESTION (Load Balancing)", cAmber);
  } 
  // 3. ACCIDENT
  else if (state.equals("ACCIDENT")) {
    targetColor = cRed; trafficLightStatus = 2; 
    signalTimingText = "ALL RED PHASE\nEmergency Perimeter Secured.";
    decisionAction = "[CRITICAL] Accident detected. Hard-closing lanes. Dispatching 108 & 100. Spillover mapping initiated." + weatherMod;
    policyConstraint = "EMS-3: Halt incoming traffic to prevent secondary collisions and secure scene for first responders immediately.";
    explainability = "Kinetic anomaly or stopped vehicle cluster detected. Dispatching medical and securing the perimeter via multi-modal traffic lights.";
    logEmergency("108 (MEDICAL) DISPATCHED: Potential casualties at collision site.", cRed);
    logEmergency("100 (POLICE) DISPATCHED: Traffic control and accident report.", cRed);
    logV2X("[TX] URGENT BROADCAST: HARD_BRAKE_ACCIDENT_AHEAD", cRed);
  }
  // 4. PEDESTRIAN ON ROAD
  else if (state.equals("PEDESTRIAN ON ROAD")) {
    targetColor = cPurple; trafficLightStatus = 2; 
    signalTimingText = "ALL RED PHASE\nVRU (Vulnerable Road User) Lock";
    decisionAction = "[URGENT] Pedestrian outside crosswalk. Warning beacons ON. Approaching AVs signaled to halt." + weatherMod;
    policyConstraint = "Safety-1.A: Vulnerable Road User (VRU) protection strictly supersedes all throughput/efficiency policies.";
    explainability = "VRU detected in live vehicle path. Hard stop initiated for all conflicting phases to prevent fatal collision.";
    logV2X("[TX] URGENT BROADCAST: SLOW_DOWN_PEDESTRIAN_AHEAD", cPurple);
  }
  // 5. CONSTRUCTION
  else if (state.equals("CONSTRUCTION")) {
    targetColor = cAmber; trafficLightStatus = 1; 
    signalTimingText = "FLASHING YELLOW\nWorkzone Caution Enabled.";
    decisionAction = "[ALERT] Workzone identified. Speed limit reduced via V2X. Extended clearance timing active." + weatherMod;
    policyConstraint = "C-2: Construction zones require -15km/h speed limit enforcement and visual caution states for human drivers.";
    explainability = "Cones, machinery, or worker vests detected. Modifying corridor flow to protect active worksite.";
    logV2X("[TX] BROADCAST: REDUCE_SPEED_WORKZONE_AHEAD", cAmber);
  }
  // 6. AMBULANCE
  else if (state.equals("AMBULANCE")) {
    targetColor = cBlue; trafficLightStatus = 0; 
    signalTimingText = "PREEMPTION HOLD\nInfinite Green until cleared.";
    decisionAction = "[EMERGENCY] V2X Green Wave Preemption active. Broadcasting 'Clear Left Lane' to surrounding vehicles." + weatherMod;
    policyConstraint = "EMS-1: First responder vehicles require immediate path clearing via absolute signal preemption.";
    explainability = "Emergency vehicle visual/acoustic signature recognized. Suspending standard logic to minimize transit time.";
    logV2X("[TX] BROADCAST: MOVE_RIGHT_EMERGENCY_VEHICLE", cBlue);
  }
  // 7. PROTESTORS
  else if (state.equals("PROTESTORS")) {
    targetColor = cRed; trafficLightStatus = 2; 
    signalTimingText = "ALL RED PHASE\nCorridor Completely Closed.";
    decisionAction = "[ALERT] Unlawful mass anomaly detected. Diverting all traffic. Notifying City Operations." + weatherMod;
    policyConstraint = "P-4.2: Mass pedestrian anomaly requires complete artery shutdown to ensure public safety.";
    explainability = "Large crowd identified occupying vehicle lanes. Cannot guarantee safe passage. Halting flow to prevent escalation.";
    logEmergency("100 (POLICE) DISPATCHED: Crowd control anomaly at Junction.", cRed);
    logV2X("[TX] BROADCAST: ROAD_CLOSED_AHEAD_CROWD", cRed);
  }
}

// This aggressive parsing ensures your live classification works regardless of exact serial formatting.
void serialEvent(Serial p) {
  try {
    String inString = p.readStringUntil('\n');
    if (inString != null) {
      inString = inString.trim().toUpperCase();
      if (inString.length() == 0) return;
      
      logV2X("RX: " + inString, textSecondary);
      
      String[] validClasses = {"NORMAL TRAFFIC", "HEAVY TRAFFIC", "ACCIDENT", 
                               "PEDESTRIAN ON ROAD", "CONSTRUCTION", "AMBULANCE", "PROTESTORS"};
      
      boolean foundClass = false;
      for (String vClass : validClasses) {
        if (inString.contains(vClass)) {
          currentDetection = vClass;
          foundClass = true;
          break;
        }
      }
      
      if (foundClass) {
        // Extract Confidence using Regex (looks for numbers like 0.95 or 95.0)
        Matcher m = Pattern.compile("\\d+\\.\\d+").matcher(inString);
        float parsedConf = targetConfidence; // fallback
        while (m.find()) {
          float val = Float.parseFloat(m.group());
          if (val > 0.0 && val <= 1.0) parsedConf = val;
          else if (val > 1.0 && val <= 100.0) parsedConf = val / 100.0f;
        }
        
        targetConfidence = parsedConf;
        updateDecisionEngine(currentDetection, targetConfidence);
        
        simulationMode = false;
        lastLiveDataTime = millis();
      }
    }
  } catch (Exception e) {
    println("Serial read error: " + e.getMessage());
  }
}

void simulateIncomingData() {
  String[] classes = {"NORMAL TRAFFIC", "HEAVY TRAFFIC", "ACCIDENT", "PEDESTRIAN ON ROAD", "CONSTRUCTION", "AMBULANCE", "PROTESTORS"};
  float[] weights = {0.4, 0.15, 0.1, 0.1, 0.1, 0.05, 0.1}; // 40% chance normal
  
  float r = random(1); float sum = 0;
  for (int i = 0; i < classes.length; i++) {
    sum += weights[i];
    if (r <= sum) {
      currentDetection = classes[i];
      break;
    }
  }
  targetConfidence = random(0.85, 0.99);
  logV2X("SIM_RX: " + currentDetection + ", " + targetConfidence, textSecondary);
  updateDecisionEngine(currentDetection, targetConfidence);
}

void cycleWeather() {
  String[] w = {"CLEAR", "RAIN", "FOG"};
  int idx = 0;
  for (int i = 0; i < w.length; i++) { if (w[i].equals(weatherCondition)) idx = i; }
  weatherCondition = w[(idx + 1) % w.length];
  logV2X("[ENV] Weather updated: " + weatherCondition, accentPrimary);
}

void logV2X(String msg, color c) {
  String t = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
  v2xLogs.add(new LogEntry(t, msg, c));
  if (v2xLogs.size() > 50) v2xLogs.remove(0); 
}

void logEmergency(String msg, color c) {
  String t = nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
  emergencyLogs.add(new LogEntry(t, msg, c));
  if (emergencyLogs.size() > 50) emergencyLogs.remove(0);
}
