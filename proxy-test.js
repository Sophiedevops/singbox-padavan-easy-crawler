(function () {
    'use strict';

    if (window.proxy_plugin_running) return;
    window.proxy_plugin_running = true;

    var proxyKey = 'proxy_custom_ip';
    var defaultProxy = '192.168.1.1:1081';

    // Записываем дефолт, если пусто
    if (!Lampa.Storage.get(proxyKey)) {
        Lampa.Storage.set(proxyKey, defaultProxy);
    }

    function initProxyPlugin() {
        // Добавляем КНОПКУ, которая вызовет клавиатуру
        Lampa.SettingsApi.addParam({
            component: 'server',
            param: {
                name: 'proxy_btn_edit',
                type: 'button'
            },
            field: {
                name: 'Настроить прокси для видео',
                description: 'Текущий: ' + (Lampa.Storage.get(proxyKey) || 'Отключен (напрямую)')
            },
            onChange: function () {
                Lampa.Input.edit({
                    title: 'IP:PORT (оставьте пустым для откл.)',
                    value: Lampa.Storage.get(proxyKey) || '',
                    free: true,
                    nosave: true
                }, function (new_value) {
                    Lampa.Storage.set(proxyKey, new_value);
                    Lampa.Noty.show('Прокси сохранен: ' + (new_value || 'Отключен'));
                    // Чтобы описание кнопки обновилось, просим переоткрыть настройки
                    setTimeout(function(){ Lampa.Noty.show('Перезайдите в настройки для обновления статуса'); }, 1500);
                });
            }
        });

        // Аккуратный перехват ссылки плеера
        var originalPlay = Lampa.Player.play;
        Lampa.Player.play = function (data) {
            var proxy = Lampa.Storage.get(proxyKey);
            
            if (data && data.url && proxy && proxy.trim() !== '') {
                var cleanProxy = proxy.replace(/^(https?:\/\/)/, '').replace(/\/$/, '').trim();
                data.url = 'http://' + cleanProxy + '/?url=' + encodeURIComponent(data.url);
            }
            
            originalPlay.call(Lampa.Player, data);
        };
    }

    // Ждем готовности Лампы
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
