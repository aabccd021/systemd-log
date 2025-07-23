const Priority = {
  debug: 7,
  info: 6,
  notice: 5,
  warning: 4,
  err: 3,
  crit: 2,
  alert: 1,
  emerg: 0,
};

export type Priority = keyof typeof Priority;

export function log(priority: Priority, message: string): void {
  const code = Priority[priority];

  if (priority === "debug") {
    console.debug(`<${code}> ${message}`);
  }

  if (priority === "info") {
    console.info(`<${code}> ${message}`);
    return;
  }

  if (priority === "notice") {
    console.log(`<${code}> ${message}`);
    return;
  }

  if (priority === "warning") {
    console.warn(`<${code}> ${message}`);
    return;
  }

  console.error(`<${code}> ${message}`);
}
