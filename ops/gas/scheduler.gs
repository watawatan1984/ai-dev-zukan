const TIME_ZONE = "Asia/Tokyo";
const START_HOUR = 10;
const END_HOUR = 20;
const SCHEDULER_HANDLER = "schedulerTick";

/**
 * 10分ごとの時間主導トリガーから呼び出す。
 * 10:00–20:59 JSTだけRenderを起こし、Rails側は同一時間帯の重複ジョブを拒否する。
 */
function schedulerTick() {
  const now = new Date();
  const hour = Number(Utilities.formatDate(now, TIME_ZONE, "H"));
  if (hour < START_HOUR || hour > END_HOUR) {
    return { status: "skipped", reason: "outside_active_hours" };
  }

  return sendSchedulerTick_(now);
}

/** 時間帯に関係なく、RenderとSupabaseへの署名付き疎通を手動確認する。 */
function testSchedulerConnection() {
  return sendSchedulerTick_(new Date());
}

function sendSchedulerTick_(now) {
  const properties = PropertiesService.getScriptProperties();
  const endpoint = properties.getProperty("SCHEDULER_TICK_URL");
  const secret = properties.getProperty("GAS_SCHEDULER_SECRET");
  if (!endpoint || !secret) throw new Error("SCHEDULER_TICK_URL and GAS_SCHEDULER_SECRET are required");

  const timestamp = Math.floor(now.getTime() / 1000).toString();
  const body = "";
  const signatureBytes = Utilities.computeHmacSha256Signature(`${timestamp}.${body}`, secret);
  const signature = signatureBytes.map(byte => (byte < 0 ? byte + 256 : byte).toString(16).padStart(2, "0")).join("");

  const response = UrlFetchApp.fetch(endpoint, {
    method: "post",
    payload: body,
    contentType: "text/plain",
    headers: {
      "X-Scheduler-Timestamp": timestamp,
      "X-Scheduler-Signature": signature
    },
    muteHttpExceptions: true
  });

  const status = response.getResponseCode();
  if (status < 200 || status >= 300) {
    throw new Error(`scheduler tick failed: HTTP ${status} ${response.getContentText()}`);
  }

  const result = JSON.parse(response.getContentText());
  if (!result.database || result.database.status !== "reachable") {
    throw new Error("scheduler tick did not confirm database reachability");
  }

  console.log(JSON.stringify({
    status: result.status,
    database: result.database,
    checkedAt: new Date().toISOString()
  }));
  return result;
}

/** 既存の同名トリガーを整理し、10分間隔を1件だけ登録する。 */
function installSchedulerTrigger() {
  const diagnostics = schedulerDiagnostics();
  if (!diagnostics.endpointConfigured || !diagnostics.secretConfigured) {
    throw new Error("SCHEDULER_TICK_URL and GAS_SCHEDULER_SECRET are required");
  }

  ScriptApp.getProjectTriggers()
    .filter(trigger => trigger.getHandlerFunction() === SCHEDULER_HANDLER)
    .forEach(trigger => ScriptApp.deleteTrigger(trigger));

  ScriptApp.newTrigger(SCHEDULER_HANDLER).timeBased().everyMinutes(10).create();
  return schedulerDiagnostics();
}

/** schedulerTickトリガーだけを削除し、他のApps Scriptトリガーは保持する。 */
function uninstallSchedulerTriggers() {
  const triggers = ScriptApp.getProjectTriggers()
    .filter(trigger => trigger.getHandlerFunction() === SCHEDULER_HANDLER);
  triggers.forEach(trigger => ScriptApp.deleteTrigger(trigger));
  return { removedCount: triggers.length };
}

/** URLや秘密値そのものを出力せず、設定有無とトリガー数だけを返す。 */
function schedulerDiagnostics() {
  const properties = PropertiesService.getScriptProperties();
  const triggerCount = ScriptApp.getProjectTriggers()
    .filter(trigger => trigger.getHandlerFunction() === SCHEDULER_HANDLER)
    .length;
  return {
    timeZone: TIME_ZONE,
    activeHours: `${START_HOUR}:00-${END_HOUR}:59`,
    intervalMinutes: 10,
    endpointConfigured: Boolean(properties.getProperty("SCHEDULER_TICK_URL")),
    secretConfigured: Boolean(properties.getProperty("GAS_SCHEDULER_SECRET")),
    triggerCount: triggerCount
  };
}
