document.addEventListener("DOMContentLoaded", () => {

    console.log("IPPLIAP · Prototipo B · interfaz PS2 activa");

    const input = document.querySelector("#document");
    const preview = document.querySelector("#photo-preview");
    const previewWrap = document.querySelector("#preview-wrap");
    const clearButton = document.querySelector("#clear-photo");
    const form = document.querySelector("#capture-form");
    const processing = document.querySelector("#processing-message");
    const qualityBanner = document.querySelector("#quality-banner");

    if (input && preview && previewWrap) {

        input.addEventListener("change", () => {

            const file = input.files?.[0];

            if (!file) {
                return;
            }

            const reader = new FileReader();

            reader.onload = (event) => {

                preview.src = event.target.result;

                previewWrap.classList.remove("hidden");

                if (qualityBanner) {

                    qualityBanner.innerHTML = `
                        <span class="quality-light"></span>
                        <div>
                            <strong>Fotografía seleccionada</strong>
                            <small>Revise la vista previa antes de analizar.</small>
                        </div>
                    `;

                }

            };

            reader.readAsDataURL(file);

        });

    }


    if (clearButton && input && previewWrap && preview) {

        clearButton.addEventListener("click", () => {

            input.value = "";

            preview.removeAttribute("src");

            previewWrap.classList.add("hidden");

            if (qualityBanner) {

                qualityBanner.innerHTML = `
                    <span class="quality-light"></span>
                    <div>
                        <strong>Preparado para capturar</strong>
                        <small>Coloque una sola hoja dentro del recuadro.</small>
                    </div>
                `;

            }

        });

    }


    if (form && processing) {

        form.addEventListener("submit", () => {

            processing.classList.remove("hidden");

        });

    }

});

