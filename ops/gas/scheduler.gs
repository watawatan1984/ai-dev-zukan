const TIME_ZONE = "Asia/Tokyo";
const START_HOUR = 10;
const END_HOUR = 20;

/**
 * 10分ごとの時間主導トリガーから呼び出す。
 * 10:00–20:59 JSTだけRenderを起こし、Rails側は同一時間帯の重複ジョブを拒否する。
 */
function schedulerTick() {
  const now = new Date();
  const hour = Number(Utilities.formatDate(now, TIME_ZONE, "H"));
  if (hour < START_HOUR || hour > END_HOUR) return;

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
}

/** 既存の同名トリガーを整理し、10分間隔を1件だけ登録する。 */
function installSchedulerTrigger() {
  ScriptApp.getProjectTriggers()
    .filter(trigger => trigger.getHandlerFunction() === "schedulerTick")
    .forEach(trigger => ScriptApp.deleteTrigger(trigger));

  ScriptApp.newTrigger("schedulerTick").timeBased().everyMinutes(10).create();
}
