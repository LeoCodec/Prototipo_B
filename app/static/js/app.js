document.addEventListener("DOMContentLoaded", () => {

    const input = document.querySelector("#document");
    const previewWrap = document.querySelector("#preview-wrap");
    const preview = document.querySelector("#photo-preview");
    const previewName = document.querySelector("#preview-name");
    const clearButton = document.querySelector("#clear-photo");
    const captureForm = document.querySelector("#capture-form");
    const processingOverlay = document.querySelector("#processing-overlay");

    if (input) {
        input.addEventListener("change", () => {

            const file = input.files && input.files[0];

            if (!file) {
                return;
            }

            if (preview) {
                preview.src = URL.createObjectURL(file);
            }

            if (previewName) {
                previewName.textContent = file.name || "Fotografía seleccionada";
            }

            if (previewWrap) {
                previewWrap.classList.remove("hidden");
            }
        });
    }


    if (clearButton && input) {
        clearButton.addEventListener("click", () => {

            input.value = "";

            if (preview) {
                preview.removeAttribute("src");
            }

            if (previewWrap) {
                previewWrap.classList.add("hidden");
            }
        });
    }


    if (captureForm) {
        captureForm.addEventListener("submit", () => {

            if (processingOverlay) {
                processingOverlay.classList.remove("hidden");

                const stages = processingOverlay.querySelectorAll(".processing-stage");

                let stageIndex = 0;

                const timer = setInterval(() => {

                    if (stageIndex < stages.length) {
                        stages.forEach((stage, index) => {
                            stage.classList.toggle("stage-active", index <= stageIndex);
                        });

                        stageIndex += 1;
                    } else {
                        clearInterval(timer);
                    }

                }, 650);
            }
        });
    }

});
