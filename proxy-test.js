(function () {
    'use strict';

    if (window.streamproxy_step1_loaded) return;
    window.streamproxy_step1_loaded = true;

    // Эту функцию мы вызовем ТОЛЬКО тогда, когда таймер подтвердит, что ядро Лампы 100% загружено
    function startPlugin() {
        var i18n = {
            ru: {
                title: 'Прокси потока (Шаг 1)',
                desc: 'Таймер отработал идеально! Плагин выжил.',
                notify: 'Интерфейс отрисован, локализация работает.'
            },
            en: {
                title: 'StreamProxy (Step 1)',
                desc: 'Timer worked perfectly! Plugin survived.',
                notify: 'Interface rendered, localization works.'
            }
        };

        function getLang(key) {
            var lang = (Lampa.Storage.get('language') || 'en').toLowerCase();
            var dict = i18n[lang] ? i18n[lang] : i18n['ru'];
            return dict[key] || key;
        }

        Lampa.SettingsApi.addParam({
            component: 'player', 
            param: {
                name: 'streamproxy_dummy_btn',
                type: 'button'
            },
            field: {
                name: getLang('title'),
                description: getLang('desc')
            },
            onChange: function () {
                Lampa.Noty.show(getLang('notify'));
            }
        });
    }

    // Железобетонный метод ожидания без обращения к объекту Lampa напрямую
    if (window.appready) {
        startPlugin();
    } else {
        // Запускаем тихий таймер: проверяем готовность каждые 200 миллисекунд
        var checkReadyTimer = setInterval(function () {
            // Если флаг appready поднят И объект Lampa существует в памяти
            if (window.appready && window.Lampa && window.Lampa.SettingsApi) {
                clearInterval(checkReadyTimer); // Убиваем таймер, он больше не нужен
                startPlugin();                  // Запускаем отрисовку
            }
        }, 200);
    }
})();
