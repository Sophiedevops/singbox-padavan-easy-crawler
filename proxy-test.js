(function () {
    'use strict';

    if (window.proxy_step1_initialized) return;
    window.proxy_step1_initialized = true;

    function initStepOne() {
        Lampa.SettingsApi.addParam({
            component: 'player', // Цепляемся к железобетонному разделу "Плеер"
            param: {
                name: 'proxy_dummy_btn',
                type: 'button'
            },
            field: {
                name: 'Прокси (Шаг 1: Пустышка)',
                description: 'Проверка интерфейса без блокировки сети. Остальные плагины живы?'
            },
            onChange: function () {
                Lampa.Noty.show('Шаг 1: Кнопка работает! Можно двигаться дальше.');
            }
        });

        console.log('ProxyPlugin Шаг 1: успешно добавлен в Плеер');
    }

    // Ждем полной загрузки системы
    if (window.appready) {
        initStepOne();
    } else {
        Lampa.Listener.follow('app', function (e) {
            if (e.type == 'ready') {
                initStepOne();
            }
        });
    }
})();
