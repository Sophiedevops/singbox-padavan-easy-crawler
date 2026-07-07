(function () {
    'use strict';

    // Жесткая блокировка двойного запуска скрипта
    if (window.streamproxy_step1_loaded) return;
    window.streamproxy_step1_loaded = true;

    // Наш мини-словарь для локализации интерфейса
    var i18n = {
        ru: {
            title: 'Прокси потока (Шаг 1)',
            desc: 'Стерильная загрузка прошла успешно. Блокировок сети нет.',
            notify: 'Клик работает! Локализация: РУС'
        },
        en: {
            title: 'StreamProxy (Step 1)',
            desc: 'Sterile loading successful. No network blocks.',
            notify: 'Click works! Localization: ENG'
        }
    };

    // Функция-помощник для перевода
    function getLang(key) {
        // Получаем язык ядра. По умолчанию ставим английский, если язык не определен
        var lang = (Lampa.Storage.get('language') || 'en').toLowerCase();
        // Если в нашем словаре нет языка пользователя (например, uk), откатываемся к ru
        var dict = i18n[lang] ? i18n[lang] : i18n['ru'];
        return dict[key] || key;
    }

    // Основная функция отрисовки интерфейса (вызывается ТОЛЬКО когда ядро готово)
    function initPlugin() {
        Lampa.SettingsApi.addParam({
            component: 'player', // Встраиваемся в гарантированно существующий раздел "Плеер"
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

        console.log('StreamProxy Plugin: Успешно инициализирован.');
    }

    // Тотальная пассивность: ждем команду от ядра Lampa
    if (window.appready) {
        initPlugin();
    } else {
        Lampa.Listener.follow('app', function (e) {
            if (e.type == 'ready') {
                initPlugin();
            }
        });
    }
})();
