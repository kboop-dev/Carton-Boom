$b = [int][double]::Parse((Get-Date -UFormat %s))
flutter pub get
flutter build web --release --pwa-strategy=none --build-number=$b
firebase deploy --only hosting,firestore:rules
Write-Host "Publicado. Version $b"
