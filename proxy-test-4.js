(function () {
    'use strict';

    var StreamProxy = {
        storageKey: 'streamproxy_current_ip',
        defaultIP: '192.168.1.1:1081',
        isHooked: false,

        init: function () {
            if (!Lampa.Storage.get(this.storageKey)) {
                Lampa.Storage.set(this.storageKey, this.defaultIP);
            }

            this.setupUI();
            this.hookPlayer();

            setTimeout(function () {
                if (window.Lampa && window.Lampa.Noty) {
                    Lampa.Noty.show('StreamProxy 4.0: Готов к перехвату видео');
                }
            }, 1000);
        },

        setupUI: function () {
            Lampa.SettingsApi.addParam({
                component: 'server',
                param: {
                    name: 'streamproxy_btn_edit',
                    type: 'button'
                },
                field: {
                    name: 'Прокси для видео (StreamProxy)',
                    description: 'Текущий: ' + (Lampa.Storage.get(this.storageKey) || 'Отключен')
                },
                onChange: function () {
                    Lampa.Input.edit({
                        title: 'Введите IP:PORT (пусто для откл.)',
                        value: Lampa.Storage.get(StreamProxy.storageKey) || '',
                        free: true,
                        nosave: true
                    }, function (new_value) {
                        Lampa.Storage.set(StreamProxy.storageKey, new_value);
                        Lampa.Noty.show('Сохранено. Перезайдите в настройки.');
                    });
                }
            });
        },

        hookPlayer: function () {
            if (this.isHooked) return;
            this.isHooked = true;

            // Сохраняем оригинальную функцию плеера
            var originalPlay = Lampa.Player.play;

            // Переопределяем её
            Lampa.Player.play = function (data) {
                var proxyAddress = Lampa.Storage.get(StreamProxy.storageKey);

                // Если прокси задан и это действительно видео-ссылка
                if (proxyAddress && proxyAddress.trim() !== '' && data && data.url) {
                    // Очищаем адрес от случайных http://, которые мог ввести пользователь
                    var cleanProxy = proxyAddress.replace(/^(https?:\/\/)/, '').replace(/\/$/, '').trim();
                    
                    // Формируем новую ссылку: пускаем через наш прокси
                    data.url = 'http://' + cleanProxy + '/?url=' + encodeURIComponent(data.url);
                    
                    console.log('StreamProxy: Перехвачено!', data.url);
                } else {
                    console.log('StreamProxy: Пропущено (прокси отключен или нет ссылки)');
                }

                // Вызываем оригинальный плеер с подмененной (или старой) ссылкой
                originalPlay.call(Lampa.Player, data);
            };
        }
    };

    if (window.appready) {
        StreamProxy.init();
    } else {
        if (window.Lampa && window.Lampa.Listener) {
            Lampa.Listener.follow('app', function (e) {
                if (e.type == 'ready') {
                    StreamProxy.init();
                }
            });
        }
    }
})();
