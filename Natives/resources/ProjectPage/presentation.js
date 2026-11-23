// Runs in WebKit's isolated client world. Only the rendered document is shared.
function presentProject(body, markdown) {
    const article = document.querySelector("article");
    const html = markdown ? markdownit({html: true, linkify: true}).render(body) : body;
    const fragment = DOMPurify.sanitize(html, {
        USE_PROFILES: {html: true},
        ADD_TAGS: ["center"],
        FORBID_TAGS: ["style", "form", "input", "button", "textarea", "select"],
        RETURN_DOM_FRAGMENT: true
    });
    if (!markdown) article.style.setProperty("--accent", "#ff995a");
    article.appendChild(fragment);
    for (const table of article.querySelectorAll("table")) {
        const wrapper = document.createElement("div");
        wrapper.className = "table-scroll";
        table.before(wrapper);
        wrapper.appendChild(table);
    }
    for (const heading of article.querySelectorAll("h1,h2,h3,h4,h5,h6")) {
        if (!heading.id) heading.id = heading.textContent.trim().toLowerCase().replace(/\s+/g, "-");
    }
    article.addEventListener("click", event => {
        const link = event.target.closest("a[href^='#']");
        if (!link) return;
        event.preventDefault();
        const target = document.getElementById(link.hash.slice(1));
        if (target) window.webkit.messageHandlers.projectLayout.postMessage({anchor: target.getBoundingClientRect().top});
    });
    const report = () => window.webkit.messageHandlers.projectLayout.postMessage({height: Math.ceil(article.getBoundingClientRect().height)});
    new ResizeObserver(report).observe(article);
    report();
}
