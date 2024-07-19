pkgname=vblue
pkgver=1.0.3
pkgdesc="Bluetooth ustility made by VALAD47"
arch=('x86_64')
pkgrel=1
depends=('gtk4' 'lua')

package() {
    cd "$srcdir"
    install -Dm755 init.lua "{$pkgdir}/usr/bin/$pkgname"
    install -Dm644 bluetooth.lua "{$pkgdir}/usr/share/lua/5.4/bluetooth.lua"
}