pkgname=vblue
pkgver=1.1.0
pkgdesc="Bluetooth utility made by VALAD47"
arch=('x86_64')
pkgrel=1
url="https://github.com/VALAD47/vblue/"
depends=('gtk4' 'lua')

package() {
    cd "$srcdir"
    install -Dm755 main.lua "$pkgdir/usr/bin/$pkgname"
    install -Dm644 bluetooth.lua "$pkgdir/usr/share/lua/5.4/$pkgname/bluetooth.lua"
}