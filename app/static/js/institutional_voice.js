(() => {
  "use strict";

  const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;

  async function ensureMicrophonePermission() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error("mediaDevices-no-disponible");
    }

    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach((track) => track.stop());
    return true;
  }

  function friendlyError(code) {
    const map = {
      "not-allowed": "Permiso de micrófono bloqueado. Permítalo en la configuración del sitio.",
      "service-not-allowed": "El navegador bloqueó el servicio de reconocimiento de voz.",
      "audio-capture": "No se encontró un micrófono disponible.",
      "network": "El servicio de reconocimiento de voz no pudo conectarse.",
      "no-speech": "No se detectó voz. Puede volver a hablar sin salir del formulario.",
      "aborted": "El dictado fue detenido.",
      "language-not-supported": "El reconocimiento no admite español de México en este navegador.",
      "mediaDevices-no-disponible": "Este navegador o ventana no permite acceder al micrófono.",
    };
    return map[code] || ("Error de reconocimiento: " + code);
  }

  function createRecognition({ continuous = true, onText, onStart, onEnd, onError }) {
    if (!Recognition) return null;

    const recognition = new Recognition();
    recognition.lang = "es-MX";
    recognition.continuous = continuous;
    recognition.interimResults = true;
    recognition.maxAlternatives = 1;

    let finalText = "";

    recognition.onstart = () => {
      if (onStart) onStart();
    };

    recognition.onresult = (event) => {
      let interim = "";

      for (let i = event.resultIndex; i < event.results.length; i++) {
        const transcript = event.results[i][0].transcript || "";

        if (event.results[i].isFinal) {
          finalText += transcript.trim() + " ";
        } else {
          interim += transcript;
        }
      }

      if (onText) onText(finalText.trim(), interim.trim());
    };

    recognition.onerror = (event) => {
      if (onError) onError(event.error || "speech-error");
    };

    recognition.onend = () => {
      if (onEnd) onEnd(finalText.trim());
    };

    return recognition;
  }

  // ============================================================
  // DICTADO DEL NOMBRE AL CREAR EXPEDIENTE
  // ============================================================
  const caseButton = document.getElementById("caseVoiceStart");

  if (caseButton) {
    const input = document.querySelector('input[name="student_name"]');
    const status = document.getElementById("caseVoiceStatus");

    if (!Recognition) {
      caseButton.disabled = true;
      if (status) {
        status.textContent = "Dictado no disponible en este navegador. Puede escribir el nombre manualmente.";
      }
    } else {
      caseButton.addEventListener("click", async () => {
        let hadError = false;

        try {
          caseButton.disabled = true;
          status.textContent = "Solicitando acceso al micrófono...";
          await ensureMicrophonePermission();
        } catch (error) {
          caseButton.disabled = false;
          status.textContent = friendlyError(error.message || "not-allowed");
          return;
        }

        const rec = createRecognition({
          continuous: false,

          onStart: () => {
            status.textContent = "Escuchando nombre...";
          },

          onText: (finalText, interim) => {
            input.value = (finalText || interim).trim();
          },

          onError: (error) => {
            hadError = true;
            caseButton.disabled = false;
            status.textContent = friendlyError(error);
          },

          onEnd: (text) => {
            caseButton.disabled = false;

            if (text) input.value = text;

            if (!hadError) {
              status.textContent = text
                ? "Nombre transcrito. Puede corregirlo antes de crear."
                : "No se detectó voz. Intente nuevamente.";
            }
          },
        });

        try {
          rec.start();
        } catch (error) {
          caseButton.disabled = false;
          status.textContent = "No fue posible iniciar el reconocimiento de voz.";
        }
      });
    }
  }

  // ============================================================
  // FORMULARIO / PERIODICIDADES
  // ============================================================
  const form = document.getElementById("studyForm");
  if (!form) return;

  const expenseFields = [
    "predial_anual",
    "gastos_anuales",
    "vacaciones_anual",
    "renta",
    "luz",
    "agua",
    "telefono_gasto",
    "gas",
    "alimentos",
    "automovil",
    "pasajes",
    "colegiaturas",
    "vestido",
    "medico_medicinas",
    "muebles_hogar",
    "creditos_personales",
    "otros_gastos",
  ];

  const annualDefaults = new Set([
    "predial_anual",
    "gastos_anuales",
    "vacaciones_anual",
  ]);

  const periodOptions = [
    ["mensual", "Mensual"],
    ["bimestral", "Bimestral"],
    ["trimestral", "Trimestral"],
    ["cuatrimestral", "Cuatrimestral"],
    ["semestral", "Semestral"],
    ["anual", "Anual"],
  ];

  expenseFields.forEach((name) => {
    const input = form.elements.namedItem(name);
    if (!input || form.elements.namedItem(name + "_periodo")) return;

    const select = document.createElement("select");
    select.name = name + "_periodo";
    select.className = "period-select";

    periodOptions.forEach(([value, label]) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      select.appendChild(option);
    });

    const saved =
      (typeof initial !== "undefined" &&
        initial.data &&
        initial.data[name + "_periodo"]) ||
      (annualDefaults.has(name) ? "anual" : "mensual");

    select.value = saved;
    input.insertAdjacentElement("afterend", select);
  });

  // ============================================================
  // DICTADO COMPLETO DEL CASO
  // ============================================================
  const voiceBox = document.getElementById("voiceIntake");
  if (!voiceBox) return;

  const startButton = document.getElementById("voiceStart");
  const stopButton = document.getElementById("voiceStop");
  const parseButton = document.getElementById("voiceInterpret");
  const textarea = document.getElementById("voiceTranscript");
  const status = document.getElementById("voiceStatus");
  const detectedBox = document.getElementById("voiceDetected");
  const warningsBox = document.getElementById("voiceWarnings");
  const overwrite = document.getElementById("voiceOverwrite");

  let recognition = null;
  let baseText = "";
  let keepListening = false;
  let fatalError = false;
  let restartTimer = null;

  if (!Recognition) {
    startButton.disabled = true;
    stopButton.disabled = true;
    status.textContent =
      "Este navegador no ofrece reconocimiento de voz. El formulario manual sigue disponible.";
  }

  function setField(name, value) {
    if (value === undefined || value === null || value === "") return;

    const el = form.elements.namedItem(name);
    if (!el) return;

    if (String(el.value || "").trim() && !overwrite.checked) return;

    el.value = value;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function applyResult(result) {
    Object.entries(result.data || {}).forEach(([name, value]) => {
      if (name !== "dictado_original") setField(name, value);
    });

    (result.family_members || []).forEach((member) => {
      if (typeof addFamily === "function") addFamily(member);
    });

    (result.income_rows || []).forEach((income) => {
      if (typeof addIncome === "function") addIncome(income);
    });

    (result.extra_expenses || []).forEach((item) => {
      if (typeof addExtraExpense === "function") addExtraExpense(item);
    });

    if (typeof updateFamilyMeta === "function") updateFamilyMeta();
    if (typeof schedule === "function") schedule();

    const detected = result.detected || [];
    detectedBox.innerHTML = detected.length
      ? "<strong>Detectado:</strong><ul>" +
        detected.map((x) => "<li>" + String(x) + "</li>").join("") +
        "</ul>"
      : "<strong>No se detectaron campos estructurados.</strong>";

    const warnings = result.warnings || [];
    warningsBox.innerHTML = warnings.length
      ? "<strong>Revise:</strong><ul>" +
        warnings.map((x) => "<li>" + String(x) + "</li>").join("") +
        "</ul>"
      : "";

    status.textContent =
      "Dictado interpretado. Revise los campos antes de guardar.";
  }

  async function interpret() {
    const text = textarea.value.trim();

    if (!text) {
      status.textContent =
        "Primero dicte o escriba una descripción del caso.";
      return;
    }

    parseButton.disabled = true;
    status.textContent = "Interpretando dictado...";

    try {
      const response = await fetch(voiceBox.dataset.dictationUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text }),
      });

      const result = await response.json();

      if (!response.ok || !result.ok) {
        throw new Error(result.error || "dictation-error");
      }

      applyResult(result);
    } catch (error) {
      status.textContent =
        "No se pudo interpretar el dictado. La transcripción no se perdió.";
    } finally {
      parseButton.disabled = false;
    }
  }

  function restartRecognition() {
    if (!keepListening || fatalError || !recognition) return;

    clearTimeout(restartTimer);

    restartTimer = setTimeout(() => {
      if (!keepListening || fatalError) return;

      try {
        recognition.start();
        status.textContent = "Escuchando... continúe hablando.";
      } catch (_) {
        // Si Chrome todavía no liberó la sesión, esperamos otro ciclo.
      }
    }, 350);
  }

  startButton.addEventListener("click", async () => {
    if (!Recognition) return;

    fatalError = false;
    keepListening = false;

    try {
      startButton.disabled = true;
      stopButton.disabled = false;
      status.textContent = "Solicitando acceso al micrófono...";
      await ensureMicrophonePermission();
    } catch (error) {
      startButton.disabled = false;
      stopButton.disabled = true;
      status.textContent = friendlyError(error.message || "not-allowed");
      return;
    }

    baseText = textarea.value.trim();
    keepListening = true;

    recognition = createRecognition({
      continuous: true,

      onStart: () => {
        status.textContent =
          "Escuchando... Hable normalmente. Pulse Detener cuando termine.";
      },

      onText: (finalText, interim) => {
        const prefix = baseText ? baseText + " " : "";
        textarea.value =
          prefix + finalText + (interim ? " " + interim : "");
      },

      onError: (error) => {
        const fatal = [
          "not-allowed",
          "service-not-allowed",
          "audio-capture",
          "network",
          "language-not-supported",
        ].includes(error);

        fatalError = fatal;

        if (fatal) {
          keepListening = false;
          startButton.disabled = false;
          stopButton.disabled = true;
        }

        status.textContent = friendlyError(error);
      },

      onEnd: (finalText) => {
        const prefix = baseText ? baseText + " " : "";

        if (finalText) {
          textarea.value = (prefix + finalText).trim();
        }

        if (keepListening && !fatalError) {
          status.textContent =
            "La sesión de voz se reinició automáticamente. Continúe hablando.";
          restartRecognition();
          return;
        }

        startButton.disabled = false;
        stopButton.disabled = true;

        if (!fatalError) {
          status.textContent =
            "Dictado detenido. Puede corregir la transcripción o interpretarla.";
        }
      },
    });

    try {
      recognition.start();
    } catch (error) {
      keepListening = false;
      startButton.disabled = false;
      stopButton.disabled = true;
      status.textContent =
        "No fue posible iniciar el reconocimiento de voz.";
    }
  });

  stopButton.addEventListener("click", () => {
    keepListening = false;
    fatalError = false;
    clearTimeout(restartTimer);

    if (recognition) {
      try {
        recognition.stop();
      } catch (_) {}
    }

    startButton.disabled = false;
    stopButton.disabled = true;
    status.textContent =
      "Dictado detenido. Puede corregir la transcripción o interpretarla.";
  });

  parseButton.addEventListener("click", interpret);
})();
