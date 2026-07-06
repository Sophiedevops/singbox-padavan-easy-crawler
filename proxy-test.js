(function () {
    'use strict';

    // Защита от двойного запуска (если Лампа решит загрузить скрипт дважды)
    if (window.proxy_plugin_running) return;
    window.proxy_plugin_running = true;

    function initProxyPlugin() {
        var proxyKey = 'proxy_custom_ip';
        var defaultProxy = '192.168.1.1:1081';

        // Если в памяти телевизора еще нет записи, прописываем дефолт
        if (!Lampa.Storage.get(proxyKey)) {
            Lampa.Storage.set(proxyKey, defaultProxy);
        }

        // Встраиваемся в существующий системный раздел "Сервер"
        Lampa.SettingsApi.addParam({
            component: 'server',
            param: {
                name: proxyKey,
                type: 'input',
                default: defaultProxy
            },
            field: {
                name: 'Прокси для видео',
                description: 'Формат IP:PORT. Оставьте пустым для отключения.'
            },
            onChange: function (value) {
                Lampa.Noty.show('Прокси для видео: ' + (value || 'Отключен'));
            }
        });

        // Аккуратный перехват исключительно функции плеера
        var originalPlay = Lampa.Player.play;
        Lampa.Player.play = function (data) {
            var proxy = Lampa.Storage.get(proxyKey);
            
            if (data && data.url && proxy && proxy.trim() !== '') {
                var cleanProxy = proxy.replace(/^(https?:\/\/)/, '').replace(/\/$/, '').trim();
                // Оборачиваем оригинальную ссылку в прокси
                data.url = 'http://' + cleanProxy + '/?url=' + encodeURIComponent(data.url);
            }
            
            // Запускаем плеер с подмененной ссылкой
            originalPlay.call(Lampa.Player, data);
        };

        Lampa.Noty.show('Плагин Прокси: ищите настройки в разделе Сервер');
    }

    // Ждем ПОЛНОЙ загрузки ядра Лампы, как это делают Skaz и Netfix
    if (window.appready) {
        initProxyPlugin();
    } else {
        Lampa.Listener.follow('app', function (e) {
            if (e.type == 'ready') {
                initProxyPlugin();
            }
        });
    }
})();
