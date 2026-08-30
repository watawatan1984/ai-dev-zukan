import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../../ops/gas/scheduler.gs", import.meta.url), "utf8");

function buildRuntime({ hour = 12, responseCode = 202, responseBody, initialTriggers = [] } = {}) {
  const fetchCalls = [];
  const deletedTriggers = [];
  const triggerIntervals = [];
  const triggers = initialTriggers.map(handler => ({ getHandlerFunction: () => handler }));
  const properties = new Map([
    [ "SCHEDULER_TICK_URL", "https://ai-dev-zukan.onrender.com/internal/scheduler_tick" ],
    [ "GAS_SCHEDULER_SECRET", "test-secret" ]
  ]);
  const body = responseBody ?? JSON.stringify({
    status: "enqueued",
    database: { status: "reachable", checked_at: "2026-08-30T12:00:00+09:00" }
  });
  const context = {
    Date,
    console,
    PropertiesService: {
      getScriptProperties: () => ({ getProperty: key => properties.get(key) ?? null })
    },
    Utilities: {
      formatDate: () => String(hour),
      computeHmacSha256Signature: () => [ 1, 2, 3 ]
    },
    UrlFetchApp: {
      fetch: (url, options) => {
        fetchCalls.push({ url, options });
        return {
          getResponseCode: () => responseCode,
          getContentText: () => body
        };
      }
    },
    ScriptApp: {
      getProjectTriggers: () => triggers,
      deleteTrigger: trigger => {
        deletedTriggers.push(trigger);
        triggers.splice(triggers.indexOf(trigger), 1);
      },
      newTrigger: handler => ({
        timeBased() { return this; },
        everyMinutes(minutes) {
          triggerIntervals.push(minutes);
          return this;
        },
        create() {
          const trigger = { getHandlerFunction: () => handler };
          triggers.push(trigger);
          return trigger;
        }
      })
    }
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return { context, deletedTriggers, fetchCalls, triggerIntervals, triggers };
}

test("manual connection test proves that Rails reached the database", () => {
  const { context, fetchCalls } = buildRuntime();

  const result = context.testSchedulerConnection();

  assert.equal(result.database.status, "reachable");
  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].options.method, "post");
  assert.match(fetchCalls[0].options.headers["X-Scheduler-Signature"], /^[0-9a-f]+$/);
});

test("scheduled ticks do not wake Render outside 10:00 through 20:59 JST", () => {
  const { context, fetchCalls } = buildRuntime({ hour: 21 });

  const result = context.schedulerTick();

  assert.equal(result.status, "skipped");
  assert.equal(result.reason, "outside_active_hours");
  assert.equal(fetchCalls.length, 0);
});

test("trigger tools install one schedule, report safe diagnostics, and remove it", () => {
  const runtime = buildRuntime({ initialTriggers: [ "schedulerTick", "schedulerTick", "otherTask" ] });

  const installed = runtime.context.installSchedulerTrigger();

  assert.equal(runtime.deletedTriggers.length, 2);
  assert.deepEqual(runtime.triggerIntervals, [ 10 ]);
  assert.equal(runtime.triggers.filter(trigger => trigger.getHandlerFunction() === "schedulerTick").length, 1);
  assert.equal(installed.triggerCount, 1);
  assert.equal(installed.endpointConfigured, true);
  assert.equal(installed.secretConfigured, true);
  assert.equal(Object.hasOwn(installed, "secret"), false);

  const removed = runtime.context.uninstallSchedulerTriggers();

  assert.equal(removed.removedCount, 1);
  assert.equal(runtime.triggers.filter(trigger => trigger.getHandlerFunction() === "schedulerTick").length, 0);
});
