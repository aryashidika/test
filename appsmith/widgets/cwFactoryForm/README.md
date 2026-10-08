# cwFactoryForm

Form Tambah/Ubah Pabrik di modal `mdlPabrik` (page Admin, R1). Hanya tampilan; simpan lewat `AdminCtrl.saveFactory()`.

## Default model
```js
{{ {
  key: AdminCtrl.factoryKey,          // naik setiap modal dibuka -> field diisi ulang
  form: AdminCtrl.factoryForm,        // { id, name, status }
  busy: AdminCtrl.factoryBusy,
  message: AdminCtrl.factoryMessage   // { type: 'error'|'info', text }
} }}
```

## Nilai keluar & event
| Event | Nilai di `cwFactoryForm.model` | Handler |
|---|---|---|
| `onSave` | `.name`, `.status` | `{{AdminCtrl.saveFactory()}}` |
| `onCancel` | – | `{{closeModal('mdlPabrik')}}` |

Aturan final di DB (`fn_factory_save`, `trg_factory_check`): nama unik & huruf besar, pabrik tidak bisa dinonaktifkan selama masih punya user aktif.
