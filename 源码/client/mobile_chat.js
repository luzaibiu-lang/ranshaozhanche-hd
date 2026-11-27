(() => {
  if (!globalThis.BurningChariotDevice?.mobile) return;

  const canvas = document.getElementById("canvas");
  const viewport = window.visualViewport;
  let bounds;
  let openCallback;
  let submitCallback;
  let closeCallback;
  let composing = false;
  let sequence = 0;
  let pending;

  const styles = document.createElement("style");
  styles.textContent = `
    #mobile-chat-trigger {
      position: absolute;
      z-index: 3;
      margin: 0;
      padding: 0;
      border: 0;
      background: transparent;
      touch-action: manipulation;
    }
    #mobile-chat-layer { position: fixed; inset: 0; z-index: 4 }
    #mobile-chat {
      position: absolute;
      transform: translateY(-100%);
      background: #182126;
      border-top: 1px solid #677177;
      padding: 6px max(8px, env(safe-area-inset-right)) max(6px, env(safe-area-inset-bottom)) max(8px, env(safe-area-inset-left));
      touch-action: manipulation;
    }
    #mobile-chat-fields { display: grid; grid-template-columns: minmax(0, 1fr) auto auto; gap: 6px }
    #mobile-chat-input, #mobile-chat button {
      margin: 0;
      min-height: 44px;
      border: 1px solid #717e84;
      border-radius: 4px;
      padding: 0 10px;
      font-size: 16px;
    }
    #mobile-chat-input { min-width: 0; color: #fff; background: #0d1316; font-family: inherit }
    #mobile-chat-input::placeholder { color: #b7c0c4 }
    #mobile-chat button { color: #141a1c; background: #efc672; white-space: nowrap; touch-action: manipulation }
    #mobile-chat button:disabled { opacity: .6 }
    #mobile-chat #mobile-chat-close { color: #e9eded; background: #303d43; width: 44px; font-size: 24px }
    #mobile-chat-status { margin: 0 0 5px; color: #f5d394; font-size: 13px }
    #mobile-chat-status:empty { display: none }
  `;
  document.head.append(styles);

  const trigger = document.createElement("button");
  trigger.id = "mobile-chat-trigger";
  trigger.type = "button";
  trigger.hidden = true;
  trigger.setAttribute("aria-label", "房间聊天");
  canvas.parentElement.append(trigger);

  const layer = document.createElement("div");
  layer.id = "mobile-chat-layer";
  layer.hidden = true;
  layer.innerHTML = `
    <form id="mobile-chat" aria-label="房间聊天">
      <p id="mobile-chat-status" role="status"></p>
      <div id="mobile-chat-fields">
        <input id="mobile-chat-input" type="text" maxlength="200" inputmode="text"
          enterkeyhint="send" autocomplete="off" placeholder="房间聊天" aria-label="聊天消息">
        <button id="mobile-chat-send" type="submit" disabled>发送</button>
        <button id="mobile-chat-close" type="button" aria-label="关闭聊天">×</button>
      </div>
    </form>`;
  document.body.append(layer);
  const form = layer.querySelector("form");
  const input = layer.querySelector("input");
  const send = layer.querySelector("#mobile-chat-send");
  const close = layer.querySelector("#mobile-chat-close");
  const status = layer.querySelector("#mobile-chat-status");

  function position() {
    if (bounds) {
      const [x, y, width, height, gameWidth, gameHeight] = bounds;
      const scaleX = canvas.clientWidth / gameWidth;
      const scaleY = canvas.clientHeight / gameHeight;
      trigger.style.left = canvas.offsetLeft + x * scaleX + "px";
      trigger.style.top = canvas.offsetTop + y * scaleY + "px";
      trigger.style.width = width * scaleX + "px";
      trigger.style.height = height * scaleY + "px";
    }
    if (layer.hidden) return;
    form.style.left = (viewport?.offsetLeft ?? 0) + "px";
    form.style.top = ((viewport?.offsetTop ?? 0) + (viewport?.height ?? window.innerHeight)) + "px";
    form.style.width = (viewport?.width ?? window.innerWidth) + "px";
  }

  function refreshSend() {
    send.disabled = Boolean(pending) || !input.value.trim();
    send.textContent = pending ? "发送中" : "发送";
  }

  function hide(notify) {
    if (layer.hidden) return;
    const callback = closeCallback;
    const draft = input.value;
    layer.hidden = true;
    input.blur();
    composing = false;
    submitCallback = closeCallback = null;
    if (notify) callback?.(draft);
  }

  function submit(event) {
    event.preventDefault();
    const text = input.value.trim();
    if (layer.hidden || pending || composing || !text || !submitCallback) return;
    const ticket = ++sequence;
    pending = { ticket, value: input.value };
    status.textContent = "";
    refreshSend();
    submitCallback(text, ticket);
  }

  // Keep taps and typing in the native editor out of the game input stream.
  for (const event of ["pointerdown", "pointerup", "touchstart", "touchmove", "touchend", "click", "keydown", "keyup"]) {
    layer.addEventListener(event, ev => ev.stopPropagation());
    trigger.addEventListener(event, ev => ev.stopPropagation());
  }
  layer.addEventListener("pointerdown", event => {
    if (event.target !== layer) return;
    event.preventDefault();
    hide(true);
  });
  trigger.addEventListener("click", () => openCallback?.());
  input.addEventListener("input", refreshSend);
  input.addEventListener("compositionstart", () => { composing = true; });
  input.addEventListener("compositionend", () => {
    composing = false;
    refreshSend();
  });
  input.addEventListener("keydown", event => {
    if (event.isComposing || event.keyCode === 229 || composing) return;
    if (event.key === "Enter") submit(event);
    if (event.key === "Escape") {
      event.preventDefault();
      hide(true);
    }
  });
  send.addEventListener("pointerdown", event => {
    if (!composing) event.preventDefault();
  });
  form.addEventListener("submit", submit);
  close.addEventListener("click", () => hide(true));
  window.addEventListener("resize", position);
  viewport?.addEventListener("resize", position);
  viewport?.addEventListener("scroll", position);

  globalThis.BurningChariotChat = {
    setTrigger(x, y, width, height, gameWidth, gameHeight, callback) {
      bounds = [x, y, width, height, gameWidth, gameHeight];
      openCallback = callback;
      trigger.hidden = false;
      position();
    },
    clearTrigger() {
      trigger.hidden = true;
      bounds = openCallback = null;
    },
    open(draft, onSubmit, onClose) {
      if (!layer.hidden) return;
      submitCallback = onSubmit;
      closeCallback = onClose;
      input.value = draft;
      layer.hidden = false;
      refreshSend();
      position();
      input.focus({ preventScroll: true });
      input.setSelectionRange(input.value.length, input.value.length);
    },
    close() {
      hide(false);
      pending = null;
      status.textContent = "";
    },
    resolve(success, message, ticket) {
      if (!pending || (ticket !== undefined && ticket !== pending.ticket)) return;
      const submitted = pending.value;
      pending = null;
      status.textContent = success ? "" : String(message || "消息发送失败，请重试");
      if (success && input.value === submitted) {
        input.value = "";
        if (!layer.hidden) hide(true);
        else return true;
      }
      refreshSend();
      return false;
    },
    isOpen() {
      return !layer.hidden;
    },
  };
})();
