/**
 * Kampung Digital Kiarajangkung
 * Google Drive photo API + provisioning akun warga dari Sensus Penduduk.
 * Deploy Web App: Execute as Me; Who has access: Anyone.
 * Script Properties wajib:
 *   DRIVE_FOLDER_ID = ID folder khusus foto
 *   FIREBASE_PROJECT_ID = kiarajangkung-app
 * API key Firebase dikirim dari aplikasi (bukan rahasia); token Firebase diverifikasi server.
 */
function doGet() {
  return json_({
    ok: true,
    message: 'Kampung Digital API aktif.',
    build: 'SOS-FCM-CODEGS-20261118-V5'
  });
}

function doPost(e) {
  var data = {};
  var tahap = 'mulai';
  try {
    tahap = 'membaca permintaan';
    data = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    tahap = 'memeriksa project';
    var projectId = getProjectId_(data.projectId);
    // Pendaftaran warga adalah satu-satunya aksi publik. Endpoint ini hanya
    // membuat permintaan tertunda; tidak membuat akun Firebase sebelum disetujui.
    if (data.action === 'requestResidentAccount') {
      tahap = 'permintaan pendaftaran warga';
      return json_(requestResidentAccount_(data, data.apiKey, projectId));
    }
    tahap = 'memeriksa token Firebase';
    var uid = verifyFirebaseToken_(data.idToken, data.apiKey);
    tahap = 'memeriksa aksi';

    // Jalur pemulihan Owner harus diperiksa sebelum validasi status Aktif.
    // Jika status profil sedang rusak/kosong, pemulihan tetap dapat berjalan
    // selama token Firebase valid dan profil pemanggil memang memiliki role Owner.
    if (data.action === 'restoreOwnerNikAccount') {
      tahap = 'jalur pemulihan Owner';
      verifyOwnerForRecovery_(uid, data.idToken, data.apiKey, projectId);
      return json_(restoreOwnerNikAccount_(uid, data.apiKey, projectId, data.idToken));
    }

    tahap = 'pemeriksaan status akun';
    var activeProfile = verifyActiveUser_(uid, data.idToken, data.apiKey, projectId);

    if (data.action === 'sendSosNotification') {
      tahap = 'mengirim notifikasi SOS ke Owner/Admin, Kawil, RW, dan RT';
      return json_(sendSosNotification_(data, uid, data.apiKey, projectId));
    }

    if (data.action === 'approveResidentAccount') {
      tahap = 'persetujuan pendaftaran warga';
      return json_(approveResidentAccount_(data, uid, activeProfile, data.idToken, data.apiKey, projectId));
    }
    if (data.action === 'rejectResidentAccount') {
      tahap = 'penolakan pendaftaran warga';
      return json_(rejectResidentAccount_(data, uid, activeProfile, data.idToken, data.apiKey, projectId));
    }

    if (data.action === 'resetResidentAccount') {
      tahap = 'reset akun warga';
      // Sesuai kebijakan aplikasi: Owner DAN Admin boleh reset akun warga.
      // Ketua RT tidak memiliki akses ke endpoint ini.
      verifyAdmin_(uid, data.idToken, data.apiKey, projectId);
      return json_(resetResidentAccount_(
        data, uid, data.idToken, data.apiKey, projectId
      ));
    }

    if (data.action === 'assignWilayahRole') {
      verifyOwner_(uid, data.idToken, data.apiKey, projectId);
      return json_(assignWilayahRole_(data, uid, data.idToken, data.apiKey, projectId));
    }

    if (data.action === 'provisionResident') {
      verifyAdmin_(uid, data.idToken, data.apiKey, projectId);
      return json_(provisionResident_(data, data.apiKey, projectId, uid, data.idToken));
    }

    if (data.action === 'upload') {
      var module = String(data.module || 'umum').replace(/[^a-zA-Z0-9_-]/g, '_').substring(0, 50);
      // Foto profil boleh diunggah oleh pemilik akun. Modul lain hanya Owner/Admin.
      if (module === 'profil') {
        // Upload foto profil pribadi diperbolehkan untuk semua akun yang tokennya valid.
      } else if (module === 'organisasi' && data.docId) {
        try {
          verifyOrganizationChair_(uid, data.docId, data.idToken, data.apiKey, projectId);
        } catch (chairError) {
          verifyAdmin_(uid, data.idToken, data.apiKey, projectId);
        }
      } else {
        verifyAdmin_(uid, data.idToken, data.apiKey, projectId);
      }
      var folderId = PropertiesService.getScriptProperties().getProperty('DRIVE_FOLDER_ID');
      if (!folderId) throw new Error('Script Property DRIVE_FOLDER_ID belum diatur.');
      var folder = DriveApp.getFolderById(folderId);
      var base64 = String(data.base64 || '');
      if (!base64) throw new Error('Data foto kosong.');
      if (base64.length > 1450000) throw new Error('Foto terlalu besar. Maksimal 1 MB.');
      var bytes = Utilities.base64Decode(base64);
      if (bytes.length > 1024 * 1024) throw new Error('Foto melebihi batas 1 MB.');
      var mime = String(data.mimeType || 'image/jpeg');
      if (['image/jpeg', 'image/png', 'image/webp'].indexOf(mime) < 0) {
        throw new Error('Format foto tidak didukung.');
      }
      var safeName = String(data.fileName || ('foto-' + Date.now() + '.jpg'))
        .replace(/[^a-zA-Z0-9._-]/g, '_').substring(0, 100);
      var blob = Utilities.newBlob(bytes, mime, module + '_' + safeName);
      var file = folder.createFile(blob);
      file.setDescription('Kampung Digital Kiarajangkung | modul=' + module + ' | uid=' + uid);
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      return json_({
        ok: true,
        fileId: file.getId(),
        imageUrl: 'https://drive.google.com/uc?export=view&id=' + file.getId()
      });
    }

    if (data.action === 'delete') {
      var fileId = String(data.fileId || '');
      if (!fileId) throw new Error('ID foto tidak ditemukan.');
      var folderIdForDelete = PropertiesService.getScriptProperties().getProperty('DRIVE_FOLDER_ID');
      if (!folderIdForDelete) throw new Error('Script Property DRIVE_FOLDER_ID belum diatur.');
      var file = DriveApp.getFileById(fileId);
      var parents = file.getParents();
      var belongsToFolder = false;
      while (parents.hasNext()) {
        if (parents.next().getId() === folderIdForDelete) belongsToFolder = true;
      }
      if (!belongsToFolder) throw new Error('Foto bukan milik folder aplikasi.');
      var description = file.getDescription() || '';
      if (description.indexOf('uid=' + uid) < 0) {
        throw new Error('Hanya pengunggah foto yang dapat menghapus file ini.');
      }
      file.setTrashed(true);
      return json_({ ok: true, message: 'Foto dipindahkan ke sampah Drive.' });
    }

    throw new Error('Aksi tidak dikenal.');
  } catch (err) {
    return json_({
      ok: false,
      error: String(err && err.message ? err.message : err),
      tahap: tahap,
      action: data.action || 'tidak terkirim',
      build: 'SOS-FCM-CODEGS-20261118-V5'
    });
  }
}


/**
 * Mengirim notifikasi SOS tanpa Cloud Functions (kompatibel dengan Firebase Spark).
 * Web App berjalan sebagai pemilik/deployer; OAuth token dipakai untuk membaca
 * Firestore, menulis inbox penerima, dan memanggil FCM HTTP v1.
 */
function sendSosNotification_(data, callerUid, apiKey, projectId) {
  var sosId = String(data.sosId || '').trim();
  if (!sosId || !/^[A-Za-z0-9_-]{1,150}$/.test(sosId)) {
    throw new Error('ID laporan SOS tidak valid.');
  }
  var oauthToken = ScriptApp.getOAuthToken();
  if (!oauthToken) throw new Error('OAuth Google Apps Script tidak tersedia.');

  var sos = readFirestoreDocument_(projectId, apiKey, oauthToken, 'kampung/kiarajangkung/laporan_sos/' + sosId);
  if (!sos) throw new Error('Laporan SOS tidak ditemukan.');
  if (String(sos.pemohonUid || '') !== String(callerUid)) {
    throw new Error('Akun ini bukan pembuat laporan SOS tersebut.');
  }
  var kawilId = String(sos.kawilId || '').trim();
  var rwId = String(sos.rwId || '').trim();
  var rtId = String(sos.rtId || '').trim();
  var users = listFirestoreDocuments_(projectId, apiKey, oauthToken, 'users');
  var targets = [];
  users.forEach(function(user) {
    var profile = user.data || {};
    if (String(profile.status || '').toLowerCase() !== 'aktif') return;
    var roles = Array.isArray(profile.roles) ? profile.roles.map(function(r) {
      return String(r).toLowerCase();
    }) : [];
    var primaryRole = String(profile.role || '').toLowerCase();
    var isOwnerAdmin = primaryRole === 'owner' || primaryRole === 'admin' ||
      roles.indexOf('owner') >= 0 || roles.indexOf('admin') >= 0;
    var isKawilRole = primaryRole === 'perangkat_kawil' || primaryRole === 'kawil' ||
      roles.indexOf('perangkat_kawil') >= 0 || roles.indexOf('kawil') >= 0;
    var isRwRole = primaryRole === 'ketua_rw' || roles.indexOf('ketua_rw') >= 0;
    var isRtRole = primaryRole === 'ketua_rt' || roles.indexOf('ketua_rt') >= 0;
    var isMatchingKawil = !!kawilId && isKawilRole &&
      String(profile.kawilId || '').trim() === kawilId;
    var isMatchingRw = !!rwId && isRwRole &&
      String(profile.rwId || '').trim() === rwId;
    var isMatchingRt = !!rtId && isRtRole &&
      String(profile.rtId || '').trim() === rtId;
    if (isOwnerAdmin || isMatchingKawil || isMatchingRw || isMatchingRt) {
      targets.push({ uid: user.id, profile: profile });
    }
  });

  var title = 'SOS DARURAT • ' + String(sos.jenis || 'MEMBUTUHKAN BANTUAN').toUpperCase();
  var detail = String(sos.uraian || '').trim();
  var body = String(sos.pemohonNama || 'Warga') + ' membutuhkan bantuan.' +
    (detail ? ' ' + detail : '');
  var location = String(sos.lokasiManual || '').trim();
  if (location) body += ' Lokasi: ' + location;
  var mapUrl = String(sos.lokasiMaps || '').trim();
  var stamp = { __firestoreTimestamp: new Date().toISOString() };
  var sent = 0, failed = 0, inboxWritten = 0, noToken = 0;
  var fcmErrors = [];
  var seenFcmErrors = {};
  var fcmUrl = 'https://fcm.googleapis.com/v1/projects/' +
    encodeURIComponent(projectId) + '/messages:send';

  targets.forEach(function(target) {
    var notificationId = 'sos_' + sosId;
    // Inbox persisten tetap dibuat meskipun perangkat tidak memiliki token push.
    firestorePatchDocument_(projectId, apiKey, oauthToken,
      'users/' + target.uid + '/notifikasi/' + notificationId, {
        kategori: 'darurat', jenis: 'sos', judul: title, pesan: body,
        referensiJenis: 'laporan_sos', referensiId: sosId,
        kawil: String(sos.kawil || ''), kawilId: kawilId,
        rw: String(sos.rw || ''), rwId: rwId,
        rt: String(sos.rt || ''), rtId: rtId,
        lokasiMaps: mapUrl, isRead: false, createdAt: stamp
      });
    inboxWritten++;

    var tokens = Array.isArray(target.profile.fcmTokens) ? target.profile.fcmTokens : [];
    tokens.forEach(function(tokenValue) {
      var token = typeof tokenValue === 'string' ? tokenValue :
        (tokenValue && (tokenValue.token || tokenValue.value) ? String(tokenValue.token || tokenValue.value) : '');
      if (!token) { noToken++; return; }
      var payload = { message: {
        token: token,
        notification: { title: title, body: body },
        data: { type: 'sos', sosId: sosId, screen: 'darurat', lokasiMaps: mapUrl },
        android: { priority: 'HIGH', notification: { channel_id: 'darurat', sound: 'default' } }
      }};
      try {
        var response = UrlFetchApp.fetch(fcmUrl, {
          method: 'post', contentType: 'application/json',
          headers: { Authorization: 'Bearer ' + oauthToken },
          payload: JSON.stringify(payload), muteHttpExceptions: true
        });
        if (response.getResponseCode() >= 200 && response.getResponseCode() < 300) sent++;
        else {
          failed++;
          var fcmText = response.getContentText() || '';
          var fcmSummary = summarizeFcmError_(response.getResponseCode(), fcmText);
          if (!seenFcmErrors[fcmSummary]) {
            seenFcmErrors[fcmSummary] = true;
            fcmErrors.push(fcmSummary);
          }
          console.warn('FCM gagal. HTTP ' + response.getResponseCode() + ': ' + fcmSummary);
        }
      } catch (pushError) {
        failed++;
        var exceptionSummary = 'Exception: ' + String(pushError && pushError.message ? pushError.message : pushError).substring(0, 300);
        if (!seenFcmErrors[exceptionSummary]) {
          seenFcmErrors[exceptionSummary] = true;
          fcmErrors.push(exceptionSummary);
        }
        console.warn('FCM exception: ' + exceptionSummary);
      }
    });
  });

  return {
    ok: true, message: 'Notifikasi SOS diproses.', penerimaInbox: inboxWritten,
    pushTerkirim: sent, pushGagal: failed, perangkatTanpaToken: noToken,
    detailError: fcmErrors,
    catatan: !targets.length
      ? 'Belum ditemukan akun Owner/Admin aktif atau Kawil aktif yang cocok dengan wilayah SOS.'
      : (failed > 0 ? 'FCM menolak ' + failed + ' pengiriman. ' + fcmErrors.join(' | ')
        : (sent === 0 ? 'Inbox tersimpan, tetapi belum ada token FCM pada perangkat petugas.' : ''))
  };
}


/** Ringkas error FCM untuk dikembalikan ke aplikasi tanpa membocorkan token perangkat. */
function summarizeFcmError_(httpCode, responseText) {
  var message = '';
  try {
    var parsed = JSON.parse(responseText || '{}');
    var err = parsed.error || {};
    var details = Array.isArray(err.details) ? err.details : [];
    var detailCode = '';
    details.forEach(function(item) {
      if (item && item.errorCode) detailCode = String(item.errorCode);
    });
    message = [err.status || '', detailCode, err.message || ''].filter(String).join(' / ');
  } catch (ignored) {
    message = String(responseText || 'Respons FCM kosong');
  }
  message = message.replace(/[\r\n\t]+/g, ' ').substring(0, 350);
  return 'HTTP ' + httpCode + (message ? ' — ' + message : '');
}


/**
 * Reset akun warga oleh Owner atau Admin tanpa Cloud Functions.
 * Password akun lain diubah melalui Identity Toolkit Admin REST API
 * memakai OAuth token Apps Script (bukan ID token Owner).
 *
 * Persyaratan:
 * - Akun Google pemilik/deployer Apps Script memiliki IAM role Identity Toolkit Admin.
 * - appsscript.json memuat scope cloud-platform dan script.external_request.
 * - Target UID harus sama dengan accountUid pada dokumen Sensus.
 */
function resetResidentAccount_(data, actorUid, actorToken, apiKey, projectId) {
  var wargaId = String(data.wargaId || '').trim();
  if (!wargaId || wargaId.length > 150) throw new Error('ID dokumen warga tidak valid.');

  var resident = readFirestoreDocument_(
    projectId, apiKey, actorToken,
    'kampung/kiarajangkung/sensus/' + wargaId
  );
  if (!resident) throw new Error('Data warga tidak ditemukan pada Sensus.');

  var uid = String(resident.accountUid || '').trim();
  var nik = String(resident.nik || '').replace(/\D/g, '');
  var nama = String(resident.nama || '').trim();
  if (!uid) throw new Error('accountUid kosong. Reset dibatalkan agar tidak membuat akun duplikat.');
  if (!/^\d{16}$/.test(nik)) throw new Error('NIK Sensus harus tepat 16 digit.');
  if (!nama) throw new Error('Nama warga pada Sensus kosong.');

  var statusWarga = String(resident.statusWarga || 'Aktif').trim().toLowerCase();
  if (['arsip', 'nonaktif', 'pindah', 'meninggal'].indexOf(statusWarga) >= 0) {
    throw new Error('Warga berstatus arsip/nonaktif tidak dapat direset dari daftar aktif.');
  }

  var rawDob = String(resident.tanggalLahir || '').trim();
  var digits = rawDob.replace(/\D/g, '');
  var day, month, year;
  if (/^\d{8}$/.test(digits)) {
    day = Number(digits.substring(0, 2));
    month = Number(digits.substring(2, 4));
    year = Number(digits.substring(4, 8));
  } else if (/^\d{4}-\d{2}-\d{2}$/.test(rawDob)) {
    var parts = rawDob.split('-');
    year = Number(parts[0]); month = Number(parts[1]); day = Number(parts[2]);
  } else {
    throw new Error('Tanggal lahir Sensus harus DD-MM-YYYY, DDMMYYYY, atau YYYY-MM-DD.');
  }
  var dobDate = new Date(Date.UTC(year, month - 1, day));
  if (!day || !month || !year || year < 1900 ||
      dobDate.getUTCFullYear() !== year ||
      dobDate.getUTCMonth() !== month - 1 ||
      dobDate.getUTCDate() !== day) {
    throw new Error('Tanggal lahir pada Sensus tidak valid.');
  }
  var password = String(day).padStart(2, '0') +
    String(month).padStart(2, '0') + String(year);
  var expectedEmail = nik + '@login.kiarajangkung.id';

  // OAuth token berasal dari akun Google yang menjalankan Web App.
  // Hak IAM diperiksa oleh Identity Toolkit saat endpoint admin dipanggil.
  var oauthToken = ScriptApp.getOAuthToken();
  if (!oauthToken) throw new Error('OAuth Google Apps Script tidak tersedia. Otorisasi ulang Web App.');

  var authBase = 'https://identitytoolkit.googleapis.com/v1/projects/' +
    encodeURIComponent(projectId) + '/accounts';

  var lookupResponse = UrlFetchApp.fetch(authBase + ':lookup', {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + oauthToken },
    payload: JSON.stringify({ localId: [uid] }),
    muteHttpExceptions: true
  });
  var lookupBody = JSON.parse(lookupResponse.getContentText() || '{}');
  if (lookupResponse.getResponseCode() !== 200) {
    var lookupMessage = lookupBody.error && lookupBody.error.message
      ? lookupBody.error.message : lookupResponse.getContentText();
    throw new Error('Gagal memeriksa akun Firebase Auth. Pastikan akun Google Apps Script memiliki role Identity Toolkit Admin. Detail: ' + lookupMessage);
  }
  var authUsers = lookupBody.users || [];
  if (!authUsers.length) {
    throw new Error('Akun Firebase Auth untuk accountUid ini tidak ditemukan. Tidak dibuat akun baru.');
  }
  var authUser = authUsers[0];
  if (String(authUser.localId || '') !== uid ||
      String(authUser.email || '').toLowerCase() !== expectedEmail.toLowerCase()) {
    throw new Error('UID atau email Firebase tidak cocok dengan NIK Sensus. Reset dibatalkan.');
  }
  if (authUser.disabled === true) {
    throw new Error('Akun Firebase sedang dinonaktifkan. Aktifkan akun terlebih dahulu sebelum reset.');
  }

  // Pertahankan profil dan roles yang sudah ada. Jika profil hilang,
  // buat profil dasar warga dari data Sensus tanpa membuat akun Auth baru.
  var oldProfile = readFirestoreDocument_(projectId, apiKey, actorToken, 'users/' + uid) || {};
  var oldRoles = Array.isArray(oldProfile.roles) && oldProfile.roles.length
    ? oldProfile.roles.map(function(r) { return String(r).toLowerCase().trim(); })
    : (oldProfile.role ? [String(oldProfile.role).toLowerCase().trim()] : ['warga']);
  var role = String(oldProfile.role || oldRoles[0] || 'warga').toLowerCase();
  var stamp = { __firestoreTimestamp: new Date().toISOString() };

  var restoredProfile = {
    uid: uid,
    email: expectedEmail,
    nik: nik,
    nama: nama,
    wargaId: wargaId,
    role: role,
    roles: oldRoles,
    status: oldProfile.status || 'Aktif',
    telepon: String(resident.telepon || oldProfile.telepon || ''),
    alamat: String(resident.alamat || oldProfile.alamat || ''),
    kawil: String(resident.kawil || oldProfile.kawil || ''),
    rw: String(resident.rw || oldProfile.rw || ''),
    rt: String(resident.rt || oldProfile.rt || ''),
    kawilId: String(resident.kawilId || oldProfile.kawilId || ''),
    rwId: String(resident.rwId || oldProfile.rwId || ''),
    rtId: String(resident.rtId || oldProfile.rtId || ''),
    mustChangePassword: true,
    passwordResetAt: stamp,
    passwordResetBy: actorUid,
    updatedAt: stamp
  };

  // Reset Auth terlebih dahulu; setelah berhasil, tulis profil dan metadata Sensus.
  var updateResponse = UrlFetchApp.fetch(authBase + ':update', {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + oauthToken },
    payload: JSON.stringify({ localId: uid, password: password }),
    muteHttpExceptions: true
  });
  var updateBody = JSON.parse(updateResponse.getContentText() || '{}');
  if (updateResponse.getResponseCode() !== 200) {
    var updateMessage = updateBody.error && updateBody.error.message
      ? updateBody.error.message : updateResponse.getContentText();
    throw new Error('Firebase menolak perubahan password. Detail: ' + updateMessage);
  }

  try {
    firestorePatchDocument_(projectId, apiKey, oauthToken, 'users/' + uid, restoredProfile);
    firestorePatchDocument_(projectId, apiKey, oauthToken,
      'kampung/kiarajangkung/sensus/' + wargaId, {
        akunStatus: 'Aktif',
        akunResetAt: stamp,
        akunResetOleh: actorUid
      });
    var auditId = Utilities.getUuid();
    firestorePatchDocument_(projectId, apiKey, oauthToken,
      'kampung/kiarajangkung/riwayat_akun/' + auditId, {
        aksi: 'reset_password', wargaId: wargaId, uid: uid,
        olehUid: actorUid, waktu: stamp, metode: 'tanggal_lahir_sementara'
      });
  } catch (writeError) {
    throw new Error(
      'Password Firebase sudah berhasil direset, tetapi pembaruan profil/metadata Firestore gagal. ' +
      'Jangan ulangi reset sebelum profil diperiksa. Detail: ' + writeError.message
    );
  }

  return {
    ok: true,
    wargaId: wargaId,
    uid: uid,
    message: 'Akun ' + nama +
      ' berhasil direset. Username tetap NIK; password awal DDMMYYYY. Warga wajib mengganti password setelah login.'
  };
}

/** PATCH Firestore REST; dapat membuat dokumen jika belum ada. */
function firestorePatchDocument_(projectId, apiKey, idToken, documentPath, values) {
  var base = 'https://firestore.googleapis.com/v1/projects/' +
    encodeURIComponent(projectId) + '/databases/(default)/documents/';
  var fields = {};
  Object.keys(values).forEach(function(key) {
    fields[key] = encodeFirestoreValue_(values[key]);
  });
  var query = Object.keys(values).map(function(key) {
    return 'updateMask.fieldPaths=' + encodeURIComponent(key);
  }).join('&');
  var url = base + documentPath.split('/').map(encodeURIComponent).join('/') +
    '?key=' + encodeURIComponent(apiKey) + (query ? '&' + query : '');
  var response = UrlFetchApp.fetch(url, {
    method: 'patch',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + idToken },
    payload: JSON.stringify({ fields: fields }),
    muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) {
    throw new Error('Firestore gagal menyimpan ' + documentPath + ': ' + response.getContentText());
  }
  return JSON.parse(response.getContentText() || '{}');
}

/** Membuat akun Firebase warga setelah Admin memasukkan data Sensus Penduduk. */
function provisionResident_(data, apiKey, projectId, creatorUid, creatorToken) {
  var nik = String(data.nik || '').replace(/\D/g, '');
  var nama = String(data.nama || '').trim();
  var dobRaw = String(data.tanggalLahir || '').trim();
  var dob = dobRaw.replace(/\D/g, '');
  if (!/^\d{16}$/.test(nik)) throw new Error('NIK harus tepat 16 digit.');
  if (!nama) throw new Error('Nama warga wajib diisi.');
  if (!/^\d{8}$/.test(dob)) {
    throw new Error('Tanggal lahir harus DD-MM-YYYY atau DDMMYYYY.');
  }
  var day = Number(dob.substring(0, 2));
  var month = Number(dob.substring(2, 4));
  var year = Number(dob.substring(4, 8));
  var date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    throw new Error('Tanggal lahir tidak valid.');
  }

  var allowedRoles = ['warga', 'owner', 'admin', 'perangkat_kawil', 'ketua_rw', 'ketua_rt',
    'petugas_sampah', 'pemilik_umkm', 'pemilik_fasilitas', 'ketua_organisasi', 'ketua_dkm'];
  var requestedRoles = Array.isArray(data.roles) ? data.roles.map(function(r) {
    return String(r || '').toLowerCase().trim();
  }) : ['warga'];
  requestedRoles.push('warga');
  requestedRoles = requestedRoles.filter(function(r, i, a) {
    return allowedRoles.indexOf(r) >= 0 && a.indexOf(r) === i;
  });
  if (requestedRoles.length === 0) requestedRoles = ['warga'];
  var creatorProfile = getUserProfile_(creatorUid, creatorToken, apiKey, projectId);
  var creatorRoles = Array.isArray(creatorProfile.roles) ? creatorProfile.roles.map(function(r) { return String(r).toLowerCase(); }) : [];
  var creatorIsOwner = String(creatorProfile.role || '').toLowerCase() === 'owner' || creatorRoles.indexOf('owner') >= 0;
  if (!creatorIsOwner && requestedRoles.some(function(r) { return r !== 'warga'; })) {
    throw new Error('Hanya Owner yang boleh memberikan role jabatan.');
  }
  var primaryRole = requestedRoles.filter(function(r) { return r !== 'warga'; })[0] || 'warga';
  // Pemeriksaan duplikasi NIK di server agar endpoint provisioning tidak bisa
  // membuat akun untuk NIK yang sudah dimiliki warga lain.
  assertUniqueSensusNik_(projectId, apiKey, creatorToken, nik, String(data.wargaId || '').trim());
  var kawil = String(data.kawil || '').trim();
  var rw = String(data.rw || '').trim();
  var rt = String(data.rt || '').trim();
  if (requestedRoles.indexOf('perangkat_kawil') >= 0 && !kawil) throw new Error('Isi Kawil untuk role Perangkat Kawil.');
  if (requestedRoles.indexOf('ketua_rw') >= 0 && !rw) throw new Error('Isi RW untuk role Ketua RW.');
  if (requestedRoles.indexOf('ketua_rt') >= 0 && (!rw || !rt)) throw new Error('Isi RW dan RT untuk role Ketua RT.');
  if (requestedRoles.indexOf('petugas_sampah') >= 0 && !kawil && !rw && !rt) throw new Error('Isi wilayah tugas Petugas Sampah.');

  var email = nik + '@login.kiarajangkung.id';
  var signupUrl = 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + encodeURIComponent(apiKey);
  var signupResponse = UrlFetchApp.fetch(signupUrl, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify({ email: email, password: dob, returnSecureToken: true }),
    muteHttpExceptions: true
  });
  var signup = JSON.parse(signupResponse.getContentText() || '{}');
  if (signupResponse.getResponseCode() !== 200 || !signup.localId || !signup.idToken) {
    var authMessage = signup.error && signup.error.message ? signup.error.message : 'Gagal membuat akun Firebase.';
    if (authMessage.indexOf('EMAIL_EXISTS') >= 0) {
      throw new Error('Akun untuk NIK ini sudah ada. Jangan buat akun baru; periksa Manajemen Akun.');
    }
    throw new Error(authMessage);
  }

  var now = new Date().toISOString();
  var fields = {
    nama: { stringValue: nama },
    email: { stringValue: email },
    nik: { stringValue: nik },
    telepon: { stringValue: String(data.telepon || '') },
    alamat: { stringValue: String(data.alamat || '') },
    rt: { stringValue: rt },
    rw: { stringValue: rw },
    kawil: { stringValue: kawil },
    kawilId: { stringValue: String(data.kawilId || '') },
    rwId: { stringValue: String(data.rwId || '') },
    rtId: { stringValue: String(data.rtId || '') },
    wargaId: { stringValue: String(data.wargaId || '') },
    role: { stringValue: primaryRole },
    roles: { arrayValue: { values: requestedRoles.map(function(r) { return { stringValue: r }; }) } },
    status: { stringValue: 'Aktif' },
    mustChangePassword: { booleanValue: true },
    createdFrom: { stringValue: 'sensus' },
    createdAt: { timestampValue: now },
    updatedAt: { timestampValue: now }
  };
  var createUrl = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents/users?documentId=' + encodeURIComponent(signup.localId) +
    '&key=' + encodeURIComponent(apiKey);
  var createResponse = UrlFetchApp.fetch(createUrl, {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + creatorToken },
    payload: JSON.stringify({ fields: fields }),
    muteHttpExceptions: true
  });
  var created = JSON.parse(createResponse.getContentText() || '{}');
  if (createResponse.getResponseCode() !== 200) {
    // Hapus akun Auth jika dokumen profil gagal dibuat agar tidak meninggalkan akun yatim.
    try {
      UrlFetchApp.fetch('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=' + encodeURIComponent(apiKey), {
        method: 'post', contentType: 'application/json',
        payload: JSON.stringify({ idToken: signup.idToken }), muteHttpExceptions: true
      });
    } catch (ignored) {}
    var firestoreError = created.error && created.error.message ? created.error.message : 'Profil Firestore gagal dibuat.';
    throw new Error('Akun Auth tidak jadi disimpan karena profil Firestore gagal: ' + firestoreError);
  }
  return {
    ok: true,
    uid: signup.localId,
    emailAlias: email,
    message: 'Akun warga berhasil dibuat. Password awal adalah tanggal lahir DDMMYYYY dan wajib diganti saat login pertama.'
  };
}


/**
 * Pemulihan khusus akun NIK Owner yang sedang login.
 * Identitas target diambil dari profile.wargaId milik caller, bukan dari input klien.
 * Data Sensus tetap dipakai; hanya akun Auth, profil users, dan pointer accountUid diperbarui.
 */
function restoreOwnerNikAccount_(creatorUid, apiKey, projectId, creatorToken) {
  var ownerProfile = getUserProfile_(creatorUid, creatorToken, apiKey, projectId);
  var roles = Array.isArray(ownerProfile.roles)
    ? ownerProfile.roles.map(function(r) { return String(r || '').toLowerCase().trim(); })
    : [];
  if (roles.indexOf('owner') < 0 && String(ownerProfile.role || '').toLowerCase() !== 'owner') {
    throw new Error('Pemulihan ini hanya untuk akun Owner.');
  }

  var wargaId = String(ownerProfile.wargaId || '').trim();
  var memakaiIdSensusCadangan = false;
  // ID dokumen Firestore peka huruf besar/kecil. Untuk akun Owner ini,
  // gunakan ejaan ID Sensus kanonis yang sudah dikonfirmasi.
  var idSensusOwnerKanonis = 'PAp0TEKQzpHwe7cPUXYh';
  if (!wargaId || wargaId.toLowerCase() === idSensusOwnerKanonis.toLowerCase() || wargaId.toLowerCase() === 'papotekqzphwe7cpuxyh') {
    wargaId = idSensusOwnerKanonis;
    memakaiIdSensusCadangan = true;
  }
  var base = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents';
  var sensusUrl = base + '/kampung/kiarajangkung/sensus/' + encodeURIComponent(wargaId) +
    '?key=' + encodeURIComponent(apiKey);
  var sensusResponse = UrlFetchApp.fetch(sensusUrl, {
    method: 'get', headers: { Authorization: 'Bearer ' + creatorToken }, muteHttpExceptions: true
  });
  if (sensusResponse.getResponseCode() !== 200) {
    var sensusHttpCode = sensusResponse.getResponseCode();
    var sensusBody = sensusResponse.getContentText() || '';
    var sensusDetail = sensusBody;
    try {
      var sensusErrJson = JSON.parse(sensusBody || '{}');
      sensusDetail = sensusErrJson.error && sensusErrJson.error.message
        ? sensusErrJson.error.message
        : sensusBody;
      if (sensusErrJson.error && sensusErrJson.error.status) {
        sensusDetail += ' [' + sensusErrJson.error.status + ']';
      }
    } catch (ignoredParseSensus) {}
    sensusDetail = String(sensusDetail).substring(0, 500);
    throw new Error(
      'Gagal membaca dokumen Sensus pada jalur kampung/kiarajangkung/sensus/' + wargaId +
      '. HTTP ' + sensusHttpCode + '. Detail Firebase: ' + sensusDetail +
      '. Data Sensus tidak diubah.'
    );
  }
  var sensusDoc = JSON.parse(sensusResponse.getContentText() || '{}');
  var sf = sensusDoc.fields || {};
  function sv(key) {
    return sf[key] && sf[key].stringValue !== undefined ? String(sf[key].stringValue) : '';
  }
  if (memakaiIdSensusCadangan) {
    var namaProfilOwner = String(ownerProfile.nama || '').trim().toUpperCase().replace(/\s+/g, ' ');
    var namaSensusOwner = sv('nama').trim().toUpperCase().replace(/\s+/g, ' ');
    if (!namaProfilOwner || !namaSensusOwner || namaProfilOwner !== namaSensusOwner) {
      throw new Error('ID Sensus cadangan ditemukan, tetapi nama pada profil Owner tidak cocok atau kosong. Tidak ada perubahan data.');
    }
  }
  var nik = sv('nik').replace(/\D/g, '');
  var nama = sv('nama').trim();
  var dob = sv('tanggalLahir').replace(/\D/g, '');
  if (!/^\d{16}$/.test(nik)) throw new Error('NIK pada data Sensus Owner tidak valid (harus 16 digit).');
  if (!nama) throw new Error('Nama pada data Sensus Owner kosong.');
  if (!/^\d{8}$/.test(dob)) throw new Error('Tanggal lahir pada Sensus Owner tidak valid. Format harus DDMMYYYY.');
  var day = Number(dob.substring(0, 2));
  var month = Number(dob.substring(2, 4));
  var year = Number(dob.substring(4, 8));
  var date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    throw new Error('Tanggal lahir pada Sensus Owner tidak valid.');
  }
  assertUniqueSensusNik_(projectId, apiKey, creatorToken, nik, wargaId);

  var email = nik + '@login.kiarajangkung.id';
  var signupUrl = 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' + encodeURIComponent(apiKey);
  var signupResponse = UrlFetchApp.fetch(signupUrl, {
    method: 'post', contentType: 'application/json',
    payload: JSON.stringify({ email: email, password: dob, returnSecureToken: true }),
    muteHttpExceptions: true
  });
  var signup = JSON.parse(signupResponse.getContentText() || '{}');
  if (signupResponse.getResponseCode() !== 200 || !signup.localId || !signup.idToken) {
    var authMessage = signup.error && signup.error.message ? signup.error.message : 'Gagal membuat akun login NIK.';
    if (authMessage.indexOf('EMAIL_EXISTS') >= 0) {
      throw new Error('Akun login untuk NIK ini ternyata sudah ada di Firebase Authentication. Tidak dibuat duplikat. Perlu pemeriksaan akun yang sudah ada.');
    }
    throw new Error(authMessage);
  }

  var finalRoles = roles.slice();
  if (finalRoles.indexOf('warga') < 0) finalRoles.push('warga');
  if (finalRoles.indexOf('owner') < 0) finalRoles.push('owner');
  var now = new Date().toISOString();
  function profileString(key, fallback) {
    return String(ownerProfile[key] !== undefined ? ownerProfile[key] : (fallback || ''));
  }
  var fields = {
    nama: { stringValue: nama },
    email: { stringValue: email },
    nik: { stringValue: nik },
    telepon: { stringValue: sv('telepon') || profileString('telepon') },
    alamat: { stringValue: sv('alamat') || profileString('alamat') },
    rt: { stringValue: sv('rt') || profileString('rt') },
    rw: { stringValue: sv('rw') || profileString('rw') },
    kawil: { stringValue: sv('kawil') || profileString('kawil') },
    kawilId: { stringValue: sv('kawilId') || profileString('kawilId') },
    rwId: { stringValue: sv('rwId') || profileString('rwId') },
    rtId: { stringValue: sv('rtId') || profileString('rtId') },
    wargaId: { stringValue: wargaId },
    role: { stringValue: 'owner' },
    roles: { arrayValue: { values: finalRoles.map(function(r) { return { stringValue: r }; }) } },
    status: { stringValue: 'Aktif' },
    mustChangePassword: { booleanValue: true },
    createdFrom: { stringValue: 'owner-account-recovery' },
    createdAt: { timestampValue: now },
    updatedAt: { timestampValue: now }
  };

  var profileUrl = base + '/users/' + encodeURIComponent(signup.localId) + '?key=' + encodeURIComponent(apiKey);
  var profileResponse = UrlFetchApp.fetch(profileUrl, {
    method: 'patch', contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + creatorToken },
    payload: JSON.stringify({ fields: fields }), muteHttpExceptions: true
  });
  var profileResult = JSON.parse(profileResponse.getContentText() || '{}');
  if (profileResponse.getResponseCode() !== 200) {
    try {
      UrlFetchApp.fetch('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=' + encodeURIComponent(apiKey), {
        method: 'post', contentType: 'application/json',
        payload: JSON.stringify({ idToken: signup.idToken }), muteHttpExceptions: true
      });
    } catch (ignored) {}
    var profileError = profileResult.error && profileResult.error.message ? profileResult.error.message : 'Gagal membuat profil akun Owner.';
    throw new Error('Profil akun tidak berhasil dibuat: ' + profileError);
  }

  var updateSensusUrl = sensusUrl +
    '&updateMask.fieldPaths=accountUid&updateMask.fieldPaths=akunStatus';
  var updateResponse = UrlFetchApp.fetch(updateSensusUrl, {
    method: 'patch', contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + creatorToken },
    payload: JSON.stringify({ fields: {
      accountUid: { stringValue: signup.localId },
      akunStatus: { stringValue: 'Aktif' }
    }}),
    muteHttpExceptions: true
  });
  var updateResult = JSON.parse(updateResponse.getContentText() || '{}');
  if (updateResponse.getResponseCode() !== 200) {
    // Rollback profil dan akun Auth baru jika pointer pada Sensus gagal diperbarui.
    try {
      UrlFetchApp.fetch(profileUrl, {
        method: 'delete', headers: { Authorization: 'Bearer ' + creatorToken }, muteHttpExceptions: true
      });
      UrlFetchApp.fetch('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=' + encodeURIComponent(apiKey), {
        method: 'post', contentType: 'application/json',
        payload: JSON.stringify({ idToken: signup.idToken }), muteHttpExceptions: true
      });
    } catch (ignored2) {}
    var sensusError = updateResult.error && updateResult.error.message ? updateResult.error.message : 'Gagal memperbarui tautan akun di Sensus.';
    throw new Error('Akun baru dibatalkan karena tautan Sensus gagal diperbarui: ' + sensusError);
  }

  return {
    ok: true,
    uid: signup.localId,
    emailAlias: email,
    message: 'Akun login NIK Owner berhasil dipulihkan. Gunakan password awal tanggal lahir DDMMYYYY, lalu ganti password setelah login pertama.'
  };
}

/**
 * Verifikasi khusus jalur pemulihan: token Firebase wajib valid dan profil
 * harus memiliki role Owner, tetapi status tidak diperiksa di sini.
 * Ini mencegah pemulihan terkunci oleh status akun yang justru sedang diperbaiki.
 */
function verifyOwnerForRecovery_(uid, idToken, apiKey, projectId) {
  var profile = getUserProfile_(uid, idToken, apiKey, projectId);
  var role = String(profile.role || '').toLowerCase().trim();
  var roles = Array.isArray(profile.roles)
    ? profile.roles.map(function(r) { return String(r || '').toLowerCase().trim(); })
    : [];
  if (role !== 'owner' && roles.indexOf('owner') < 0) {
    throw new Error('Pemulihan hanya dapat dilakukan oleh akun yang memiliki role Owner.');
  }
  return profile;
}

function verifyOwner_(uid, idToken, apiKey, projectId) {
  var profile = verifyActiveUser_(uid, idToken, apiKey, projectId);
  var role = String(profile.role || '').toLowerCase();
  var roles = Array.isArray(profile.roles) ? profile.roles.map(function(r) { return String(r).toLowerCase(); }) : [];
  if (role !== 'owner' && roles.indexOf('owner') < 0) {
    throw new Error('Hanya Owner yang boleh memulihkan akun NIK Owner.');
  }
}

function assertUniqueSensusNik_(projectId, apiKey, creatorToken, nik, wargaId) {
  var base = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents';
  var indexUrl = base + '/kampung/kiarajangkung/sensus_nik_index/' +
    encodeURIComponent(nik) + '?key=' + encodeURIComponent(apiKey);
  var indexResponse = UrlFetchApp.fetch(indexUrl, {
    method: 'get', headers: { Authorization: 'Bearer ' + creatorToken }, muteHttpExceptions: true
  });
  if (indexResponse.getResponseCode() === 200) {
    var indexDoc = JSON.parse(indexResponse.getContentText() || '{}');
    var indexedWargaId = indexDoc.fields && indexDoc.fields.wargaId && indexDoc.fields.wargaId.stringValue
      ? indexDoc.fields.wargaId.stringValue : '';
    if (indexedWargaId && indexedWargaId !== wargaId) {
      throw new Error('NIK sudah terhubung dengan data warga lain di Sensus.');
    }
  } else if (indexResponse.getResponseCode() !== 404) {
    throw new Error('Tidak dapat memeriksa indeks NIK: ' + indexResponse.getContentText());
  }

  var queryUrl = base + '/kampung/kiarajangkung:runQuery?key=' + encodeURIComponent(apiKey);
  var queryResponse = UrlFetchApp.fetch(queryUrl, {
    method: 'post', contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + creatorToken },
    payload: JSON.stringify({ structuredQuery: {
      from: [{ collectionId: 'sensus' }],
      where: { fieldFilter: { field: { fieldPath: 'nik' }, op: 'EQUAL', value: { stringValue: nik } } },
      limit: 5
    } }), muteHttpExceptions: true
  });
  if (queryResponse.getResponseCode() !== 200) {
    throw new Error('Pemeriksaan NIK ke Sensus gagal: ' + queryResponse.getContentText());
  }
  var rows = JSON.parse(queryResponse.getContentText() || '[]');
  rows.forEach(function(row) {
    if (!row.document || !row.document.name) return;
    var parts = row.document.name.split('/');
    var foundId = parts[parts.length - 1];
    if (foundId !== wargaId) {
      throw new Error('NIK sudah terdaftar pada data Sensus lain. Gunakan data warga yang sudah ada.');
    }
  });
}

function getProjectId_(provided) {
  var configured = PropertiesService.getScriptProperties().getProperty('FIREBASE_PROJECT_ID');
  var projectId = String(configured || provided || '').trim();
  if (!projectId) throw new Error('Script Property FIREBASE_PROJECT_ID belum diatur.');
  if (configured && provided && configured !== provided) throw new Error('Project ID Firebase tidak cocok.');
  return projectId;
}


function verifyOrganizationChair_(uid, docId, idToken, apiKey, projectId) {
  var url = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents/kampung/kiarajangkung/organisasi/' +
    encodeURIComponent(String(docId)) + '?key=' + encodeURIComponent(apiKey);
  var response = UrlFetchApp.fetch(url, {
    method: 'get', headers: { Authorization: 'Bearer ' + idToken }, muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) throw new Error('Organisasi tidak ditemukan atau tidak dapat dibaca.');
  var doc = JSON.parse(response.getContentText() || '{}');
  var ketuaUid = doc.fields && doc.fields.ketuaUid && doc.fields.ketuaUid.stringValue
    ? doc.fields.ketuaUid.stringValue : '';
  if (ketuaUid !== uid) throw new Error('Akun ini bukan Ketua organisasi tersebut.');
}

/**
 * Menetapkan ketua Kawil/RW/RT dari satu Data Sensus yang sudah memiliki akun.
 * Hanya Owner. Data warga tidak dibuat ulang; profil users, dokumen Sensus,
 * dan dokumen wilayah diperbarui dalam satu commit Firestore.
 */
function assignWilayahRole_(data, uid, idToken, apiKey, projectId) {
  var wargaId = String(data.wargaId || '').trim();
  var level = String(data.level || '').toLowerCase().trim();
  var wilayahId = String(data.wilayahId || '').trim();
  var config = {
    kawil: { collection: 'wilayah_kawil', role: 'perangkat_kawil' },
    rw: { collection: 'wilayah_rw', role: 'ketua_rw' },
    rt: { collection: 'wilayah_rt', role: 'ketua_rt' }
  }[level];
  if (!config || !wargaId || !wilayahId) throw new Error('Data penugasan wilayah tidak lengkap.');

  var sensusPath = 'kampung/kiarajangkung/sensus/' + wargaId;
  var sensus = readFirestoreDocument_(projectId, apiKey, idToken, sensusPath);
  if (!sensus) throw new Error('Data warga tidak ditemukan pada Sensus.');
  if (String(sensus.accountUid || '') !== uid) throw new Error('Warga yang dipilih belum tertaut ke akun Firebase yang benar.');
  if (String(sensus.statusWarga || 'Aktif').toLowerCase() !== 'aktif') throw new Error('Hanya warga aktif yang dapat ditetapkan sebagai petugas.');

  var profile = getUserProfile_(uid, idToken, apiKey, projectId);
  if (String(profile.status || '').toLowerCase() !== 'aktif') throw new Error('Akun petugas tidak aktif.');
  var regionPath = 'kampung/kiarajangkung/' + config.collection + '/' + wilayahId;
  var region = readFirestoreDocument_(projectId, apiKey, idToken, regionPath);
  if (!region || region.aktif === false) throw new Error('Data wilayah tidak ditemukan atau sudah nonaktif.');

  var kawilId = level === 'kawil' ? wilayahId : String(region.kawilId || '');
  var rwId = level === 'rw' ? wilayahId : (level === 'rt' ? String(region.rwId || '') : '');
  var rtId = level === 'rt' ? wilayahId : '';
  var kawilName = level === 'kawil' ? String(region.nama || '') : String(region.kawilNama || '');
  var rwName = level === 'rw' ? String(region.nama || '') : (level === 'rt' ? String(region.rwNama || '') : '');
  var rtName = level === 'rt' ? String(region.nama || '') : '';

  if (level === 'rw') {
    var parentKawil = readFirestoreDocument_(projectId, apiKey, idToken, 'kampung/kiarajangkung/wilayah_kawil/' + kawilId);
    if (!parentKawil) throw new Error('Kawil induk RW tidak ditemukan.');
    kawilName = String(parentKawil.nama || '');
  }
  if (level === 'rt') {
    var parentRw = readFirestoreDocument_(projectId, apiKey, idToken, 'kampung/kiarajangkung/wilayah_rw/' + rwId);
    if (!parentRw) throw new Error('RW induk RT tidak ditemukan.');
    var parentKawil2 = readFirestoreDocument_(projectId, apiKey, idToken, 'kampung/kiarajangkung/wilayah_kawil/' + String(parentRw.kawilId || ''));
    if (!parentKawil2) throw new Error('Kawil induk RT tidak ditemukan.');
    rwName = String(parentRw.nama || '');
    kawilId = String(parentRw.kawilId || '');
    kawilName = String(parentKawil2.nama || '');
  }

  var roles = Array.isArray(profile.roles) ? profile.roles.slice() : [];
  if (roles.indexOf('warga') < 0) roles.push('warga');
  if (roles.indexOf(config.role) < 0) roles.push(config.role);
  var primary = String(profile.role || 'warga').toLowerCase() === 'warga' ? config.role : profile.role;
  var stamp = { __firestoreTimestamp: new Date().toISOString() };
  var profilePatch = { role: primary, roles: roles, updatedAt: stamp };
  var sensusPatch = { role: primary, roles: roles, updatedAt: stamp };
  profilePatch.kawilId = kawilId; sensusPatch.kawilId = kawilId;
  profilePatch.kawil = kawilName; sensusPatch.kawil = kawilName;
  profilePatch.rwId = rwId; sensusPatch.rwId = rwId;
  profilePatch.rw = rwName; sensusPatch.rw = rwName;
  profilePatch.rtId = rtId; sensusPatch.rtId = rtId;
  profilePatch.rt = rtName; sensusPatch.rt = rtName;

  var regionPatch = {
    ketuaUid: uid,
    ketuaWargaId: wargaId,
    ketuaNama: String(sensus.nama || profile.nama || ''),
    ketuaRole: config.role,
    updatedAt: stamp,
    updatedBy: uid
  };
  var nik = String(sensus.nik || '').replace(/\D/g, '');
  if (!/^\d{16}$/.test(nik)) throw new Error('NIK warga pada Sensus tidak valid.');
  var writes = [
    firestoreUpdateWrite_(projectId, 'users/' + uid, profilePatch),
    firestoreUpdateWrite_(projectId, sensusPath, sensusPatch),
    // Pastikan indeks NIK lama ikut menunjuk ke dokumen Sensus yang sama.
    firestoreUpdateWrite_(projectId, 'kampung/kiarajangkung/sensus_nik_index/' + nik, { nik: nik, wargaId: wargaId }),
    firestoreUpdateWrite_(projectId, regionPath, regionPatch)
  ];
  commitFirestoreWrites_(projectId, apiKey, idToken, writes);
  return { ok: true, message: 'Ketua wilayah berhasil ditetapkan.', role: config.role, uid: uid, wargaId: wargaId, wilayahId: wilayahId };
}

function readFirestoreDocument_(projectId, apiKey, idToken, documentPath) {
  var url = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents/' + documentPath.split('/').map(encodeURIComponent).join('/') +
    '?key=' + encodeURIComponent(apiKey);
  var response = UrlFetchApp.fetch(url, { method: 'get', headers: { Authorization: 'Bearer ' + idToken }, muteHttpExceptions: true });
  if (response.getResponseCode() === 404) return null;
  if (response.getResponseCode() !== 200) throw new Error('Gagal membaca ' + documentPath + ': ' + response.getContentText());
  var raw = JSON.parse(response.getContentText() || '{}');
  var out = {};
  Object.keys(raw.fields || {}).forEach(function(k) { out[k] = decodeFirestoreValue_(raw.fields[k]); });
  return out;
}

function decodeFirestoreValue_(v) {
  if (v.stringValue !== undefined) return v.stringValue;
  if (v.booleanValue !== undefined) return v.booleanValue;
  if (v.integerValue !== undefined) return Number(v.integerValue);
  if (v.doubleValue !== undefined) return Number(v.doubleValue);
  if (v.timestampValue !== undefined) return v.timestampValue;
  if (v.nullValue !== undefined) return null;
  if (v.arrayValue) return (v.arrayValue.values || []).map(decodeFirestoreValue_);
  if (v.mapValue) { var o = {}; Object.keys(v.mapValue.fields || {}).forEach(function(k) { o[k] = decodeFirestoreValue_(v.mapValue.fields[k]); }); return o; }
  return null;
}

function encodeFirestoreValue_(v) {
  if (v && typeof v === 'object' && v.__firestoreTimestamp) return { timestampValue: v.__firestoreTimestamp };
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeFirestoreValue_) } };
  if (typeof v === 'object') { var fields = {}; Object.keys(v).forEach(function(k) { fields[k] = encodeFirestoreValue_(v[k]); }); return { mapValue: { fields: fields } }; }
  return { stringValue: String(v) };
}

function firestoreUpdateWrite_(projectId, documentPath, patch) {
  var fields = {};
  Object.keys(patch).forEach(function(k) { fields[k] = encodeFirestoreValue_(patch[k]); });
  return {
    update: { name: 'projects/' + projectId + '/databases/(default)/documents/' + documentPath, fields: fields },
    updateMask: { fieldPaths: Object.keys(patch) }
  };
}

function commitFirestoreWrites_(projectId, apiKey, idToken, writes) {
  var url = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents:commit?key=' + encodeURIComponent(apiKey);
  var response = UrlFetchApp.fetch(url, {
    method: 'post', contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + idToken },
    payload: JSON.stringify({ writes: writes }), muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) throw new Error('Gagal menyimpan penugasan wilayah: ' + response.getContentText());
}

/** Menolak akses API bagi akun yang tidak aktif. */
function verifyActiveUser_(uid, idToken, apiKey, projectId) {
  var profile = getUserProfile_(uid, idToken, apiKey, projectId);
  var status = String(profile.status || '').toLowerCase();
  if (status !== 'aktif') throw new Error('Akun tidak aktif atau status akun belum valid. Hubungi Owner/Admin.');
  return profile;
}

/** Hanya Owner/Admin boleh menjalankan operasi administratif. */
function verifyAdmin_(uid, idToken, apiKey, projectId) {
  var profile = verifyActiveUser_(uid, idToken, apiKey, projectId);
  var role = String(profile.role || '').toLowerCase();
  var roles = Array.isArray(profile.roles) ? profile.roles.map(function(r) { return String(r).toLowerCase(); }) : [];
  if (['owner', 'admin'].indexOf(role) < 0 &&
      !roles.some(function(r) { return r === 'owner' || r === 'admin'; })) {
    throw new Error('Hanya Owner/Admin yang boleh melakukan tindakan ini.');
  }
}

function getUserProfile_(uid, idToken, apiKey, projectId) {
  var url = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents/users/' + encodeURIComponent(uid) + '?key=' + encodeURIComponent(apiKey);
  var response = UrlFetchApp.fetch(url, {
    method: 'get', headers: { Authorization: 'Bearer ' + idToken }, muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) throw new Error('Profil akun tidak dapat diverifikasi.');
  var doc = JSON.parse(response.getContentText() || '{}');
  var fields = doc.fields || {};
  var out = {};
  Object.keys(fields).forEach(function(key) {
    var value = fields[key];
    if (value.stringValue !== undefined) out[key] = value.stringValue;
    else if (value.booleanValue !== undefined) out[key] = value.booleanValue;
    else if (value.arrayValue && value.arrayValue.values) {
      out[key] = value.arrayValue.values.map(function(v) { return v.stringValue || ''; });
    }
  });
  return out;
}

/** Memastikan token benar-benar diterbitkan Firebase Authentication. */
function verifyFirebaseToken_(idToken, apiKey) {
  if (!idToken || !apiKey) throw new Error('Token login tidak tersedia.');
  var url = 'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=' + encodeURIComponent(apiKey);
  var response = UrlFetchApp.fetch(url, {
    method: 'post', contentType: 'application/json',
    payload: JSON.stringify({ idToken: idToken }), muteHttpExceptions: true
  });
  var result = JSON.parse(response.getContentText() || '{}');
  if (response.getResponseCode() !== 200 || !result.users || !result.users.length) {
    throw new Error('Login Firebase tidak valid atau sudah kedaluwarsa.');
  }
  if (!result.users[0].localId) throw new Error('Identitas akun Firebase tidak ditemukan.');
  return result.users[0].localId;
}


/**
 * Menerima permintaan akun tanpa membuat akun Auth. NIK dan tanggal lahir
 * hanya dipakai untuk mencocokkan data Sensus; keduanya tidak disimpan.
 * Respons selalu generik agar endpoint tidak membocorkan keberadaan NIK.
 */
function requestResidentAccount_(data, apiKey, projectId) {
  var generic = {
    ok: true,
    message: 'Jika data cocok dengan Sensus dan belum memiliki akun, permintaan akan diteruskan kepada Admin dan Ketua RT.'
  };
  var nik = String(data.nik || '').replace(/\D/g, '');
  var dob = normalizeDobDigits_(data.tanggalLahir || data.tanggalLahirInput || '');
  if (!/^\d{16}$/.test(nik) || !dob) return generic;

  var lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return generic;
  try {
    var cache = CacheService.getScriptCache();
    var cacheKey = 'account_request_' + Utilities.base64EncodeWebSafe(
      Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, nik)
    ).substring(0, 24);
    if (cache.get(cacheKey)) return generic;
    var oauthToken = ScriptApp.getOAuthToken();
    if (!oauthToken) return generic;
    var index = readFirestoreDocument_(projectId, apiKey, oauthToken,
      'kampung/kiarajangkung/sensus_nik_index/' + nik);
    var wargaId = index && index.wargaId ? String(index.wargaId) : findSensusWargaIdByNik_(projectId, apiKey, oauthToken, nik);
    if (!wargaId) return generic;
    var resident = readFirestoreDocument_(projectId, apiKey, oauthToken,
      'kampung/kiarajangkung/sensus/' + wargaId);
    if (!resident || String(resident.nik || '').replace(/\D/g, '') !== nik) return generic;
    if (String(resident.accountUid || '').trim()) return generic;
    if (normalizeDobDigits_(resident.tanggalLahir || '') !== dob) return generic;

    var requestIndexPath = 'kampung/kiarajangkung/permintaan_akun_index/' + wargaId;
    var oldIndex = readFirestoreDocument_(projectId, apiKey, oauthToken, requestIndexPath);
    if (oldIndex && String(oldIndex.status || '') === 'menunggu') return generic;

    var requestId = Utilities.getUuid();
    var stamp = { __firestoreTimestamp: new Date().toISOString() };
    var requestData = {
      wargaId: wargaId,
      nama: String(resident.nama || ''),
      nikMask: nik.substring(0, 4) + '********' + nik.substring(12),
      rt: String(resident.rt || ''), rw: String(resident.rw || ''),
      rtId: String(resident.rtId || ''), rwId: String(resident.rwId || ''),
      kawilId: String(resident.kawilId || ''),
      status: 'menunggu',
      createdAt: stamp, updatedAt: stamp
    };
    firestorePatchDocument_(projectId, apiKey, oauthToken,
      'kampung/kiarajangkung/permintaan_akun/' + requestId, requestData);
    firestorePatchDocument_(projectId, apiKey, oauthToken, requestIndexPath, {
      requestId: requestId, status: 'menunggu', updatedAt: stamp
    });
    cache.put(cacheKey, '1', 300);
    try {
      notifyAccountApprovers_(projectId, apiKey, oauthToken, requestId, requestData);
    } catch (notificationError) {
      console.error('Permintaan akun tersimpan tetapi notifikasi gagal: ' + notificationError);
    }
    return generic;
  } catch (ignored) {
    // Jangan mengungkap apakah NIK/tanggal lahir cocok atau tidak.
    return generic;
  } finally {
    lock.releaseLock();
  }
}

function findSensusWargaIdByNik_(projectId, apiKey, token, nik) {
  var url = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
    '/databases/(default)/documents/kampung/kiarajangkung:runQuery?key=' + encodeURIComponent(apiKey);
  var response = UrlFetchApp.fetch(url, {
    method: 'post', contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + token },
    payload: JSON.stringify({ structuredQuery: {
      from: [{ collectionId: 'sensus' }],
      where: { fieldFilter: { field: { fieldPath: 'nik' }, op: 'EQUAL', value: { stringValue: nik } } },
      limit: 2
    } }),
    muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) return '';
  var rows = JSON.parse(response.getContentText() || '[]');
  var matches = rows.filter(function(row) {
    return row.document && row.document.name && row.document.fields &&
      row.document.fields.nik && row.document.fields.nik.stringValue === nik;
  });
  if (matches.length !== 1) return '';
  var parts = String(matches[0].document.name).split('/');
  return parts[parts.length - 1] || '';
}

function normalizeDobDigits_(value) {
  var raw = String(value || '').trim();
  var digits = raw.replace(/\D/g, '');
  if (/^\d{8}$/.test(digits)) {
    var d = Number(digits.substring(0, 2));
    var m = Number(digits.substring(2, 4));
    var y = Number(digits.substring(4, 8));
    var date = new Date(Date.UTC(y, m - 1, d));
    if (y >= 1900 && date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d) return digits;
  }
  if (/^\d{4}-\d{2}-\d{2}/.test(raw)) {
    var parts = raw.substring(0, 10).split('-');
    var year = Number(parts[0]), month = Number(parts[1]), day = Number(parts[2]);
    var parsed = new Date(Date.UTC(year, month - 1, day));
    if (year >= 1900 && parsed.getUTCFullYear() === year && parsed.getUTCMonth() === month - 1 && parsed.getUTCDate() === day) {
      return String(day).padStart(2, '0') + String(month).padStart(2, '0') + String(year);
    }
  }
  return '';
}

function accountRequestRoleSet_(profile) {
  var roles = Array.isArray(profile.roles) ? profile.roles.map(function(r) { return String(r || '').toLowerCase(); }) : [];
  if (profile.role) roles.push(String(profile.role).toLowerCase());
  return roles;
}

function verifyAccountRequestApprover_(profile, request) {
  var roles = accountRequestRoleSet_(profile);
  // Owner memiliki akses penuh: dapat melihat, menyetujui, dan menolak
  // seluruh permintaan akun tanpa batasan wilayah.
  if (roles.indexOf('owner') >= 0) return 'owner';
  if (roles.indexOf('admin') >= 0) return 'admin';
  // Ketua RT hanya dapat memproses permintaan dari RT sendiri.
  if (roles.indexOf('ketua_rt') >= 0 && String(profile.rtId || '') &&
      String(profile.rtId || '') === String(request.rtId || '')) return 'ketua_rt';
  throw new Error('Hanya Owner, Admin, atau Ketua RT sesuai wilayah warga yang dapat memproses permintaan ini.');
}

function approveResidentAccount_(data, actorUid, actorProfile, actorToken, apiKey, projectId) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) throw new Error('Permintaan akun sedang diproses petugas lain. Coba kembali.');
  try {
  var requestId = String(data.requestId || '').trim();
  if (!requestId) throw new Error('ID permintaan tidak valid.');
  var requestPath = 'kampung/kiarajangkung/permintaan_akun/' + requestId;
  var request = readFirestoreDocument_(projectId, apiKey, actorToken, requestPath);
  if (!request) throw new Error('Permintaan akun tidak ditemukan.');
  var approverRole = verifyAccountRequestApprover_(actorProfile, request);
  if (String(request.status || '') !== 'menunggu') throw new Error('Permintaan ini sudah diproses.');

  var wargaId = String(request.wargaId || '');
  var residentPath = 'kampung/kiarajangkung/sensus/' + wargaId;
  var resident = readFirestoreDocument_(projectId, apiKey, actorToken, residentPath);
  if (!resident) throw new Error('Data Sensus warga tidak ditemukan.');
  if (String(resident.accountUid || '').trim()) throw new Error('Warga sudah memiliki akun. Periksa Manajemen Akun.');
  var nik = String(resident.nik || '').replace(/\D/g, '');
  var dob = normalizeDobDigits_(resident.tanggalLahir || '');
  if (!/^\d{16}$/.test(nik) || !dob) throw new Error('NIK atau tanggal lahir pada Sensus tidak valid.');
  if (String(request.rtId || '') && String(request.rtId) !== String(resident.rtId || '')) {
    throw new Error('Wilayah warga berubah sejak permintaan dibuat. Minta warga mengajukan ulang.');
  }
  // RT hanya boleh memproses warga pada RT-nya; Admin dapat memproses semua wilayah.
  verifyAccountRequestApprover_(actorProfile, request);

  var oauthToken = ScriptApp.getOAuthToken();
  var provision = createOrRepairResidentAccount_(
    resident, wargaId, actorUid, apiKey, projectId, oauthToken
  );

  var stamp = { __firestoreTimestamp: new Date().toISOString() };
  var auditId = Utilities.getUuid();
  var writes = [
    firestoreUpdateWrite_(projectId, residentPath, {
      accountUid: provision.uid, akunStatus: 'Aktif', akunDisetujuiOleh: actorUid,
      akunDisetujuiPada: stamp, akunPermintaanId: requestId
    }),
    firestoreUpdateWrite_(projectId, requestPath, {
      status: 'disetujui', diprosesOlehUid: actorUid, diprosesOlehRole: approverRole,
      diprosesPada: stamp, updatedAt: stamp
    }),
    firestoreUpdateWrite_(projectId, 'kampung/kiarajangkung/permintaan_akun_index/' + wargaId, {
      requestId: requestId, status: 'disetujui', updatedAt: stamp
    }),
    firestoreUpdateWrite_(projectId, 'kampung/kiarajangkung/riwayat_akun/' + auditId, {
      aksi: 'pendaftaran_disetujui', wargaId: wargaId, uid: provision.uid,
      requestId: requestId, olehUid: actorUid, olehRole: approverRole, waktu: stamp
    })
  ];
  try {
    commitFirestoreWrites_(projectId, apiKey, oauthToken, writes);
  } catch (commitError) {
    // Jangan meninggalkan akun yatim yang tidak tertaut ke Sensus.
    try {
      var authBase = 'https://identitytoolkit.googleapis.com/v1/projects/' + encodeURIComponent(projectId) + '/accounts';
      UrlFetchApp.fetch(authBase + ':delete', {
        method: 'post', contentType: 'application/json',
        headers: { Authorization: 'Bearer ' + oauthToken },
        payload: JSON.stringify({ localId: provision.uid }), muteHttpExceptions: true
      });
      UrlFetchApp.fetch('https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
        '/databases/(default)/documents/users/' + encodeURIComponent(provision.uid) + '?key=' + encodeURIComponent(apiKey), {
          method: 'delete', headers: { Authorization: 'Bearer ' + oauthToken }, muteHttpExceptions: true
        });
    } catch (cleanupError) {
      throw new Error('Pembuatan akun gagal ditautkan. Pembersihan otomatis juga gagal; periksa akun UID ' + provision.uid + '. Detail: ' + cleanupError);
    }
    throw new Error('Pembuatan akun dibatalkan karena tautan ke Sensus gagal: ' + commitError);
  }
  return {
    ok: true, uid: provision.uid,
    message: 'Pendaftaran disetujui dan akun berhasil dibuat. Username adalah NIK; password sementara tanggal lahir DDMMYYYY. Warga wajib mengganti password setelah login.'
  };
  } finally {
    lock.releaseLock();
  }
}

/**
 * Jika alias NIK sudah pernah dibuat tetapi pointer accountUid hilang,
 * tautkan kembali akun yang cocok. Jangan pernah membuat akun duplikat.
 */
function createOrRepairResidentAccount_(resident, wargaId, actorUid, apiKey, projectId, oauthToken) {
  var nik = String(resident.nik || '').replace(/\D/g, '');
  var dob = normalizeDobDigits_(resident.tanggalLahir || '');
  var email = nik + '@login.kiarajangkung.id';
  var authBase = 'https://identitytoolkit.googleapis.com/v1/projects/' + encodeURIComponent(projectId) + '/accounts';
  var lookup = UrlFetchApp.fetch(authBase + ':lookup', {
    method: 'post', contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + oauthToken },
    payload: JSON.stringify({ email: [email] }), muteHttpExceptions: true
  });
  if (lookup.getResponseCode() !== 200) {
    throw new Error('Gagal memeriksa akun Firebase lama: ' + lookup.getContentText());
  }
  var body = JSON.parse(lookup.getContentText() || '{}');
  var users = body.users || [];
  if (!users.length) {
    return provisionResident_({
      nik: nik, nama: String(resident.nama || ''), tanggalLahir: dob,
      telepon: String(resident.telepon || ''), alamat: String(resident.alamat || ''),
      rt: String(resident.rt || ''), rw: String(resident.rw || ''), kawil: String(resident.kawil || ''),
      kawilId: String(resident.kawilId || ''), rwId: String(resident.rwId || ''), rtId: String(resident.rtId || ''),
      wargaId: wargaId, roles: ['warga']
    }, apiKey, projectId, actorUid, oauthToken);
  }
  var authUser = users[0];
  var uid = String(authUser.localId || '');
  if (!uid || String(authUser.email || '').toLowerCase() !== email.toLowerCase()) {
    throw new Error('Akun Firebase lama tidak cocok dengan alias NIK Sensus.');
  }
  if (authUser.disabled === true) throw new Error('Akun Firebase lama sedang dinonaktifkan. Periksa statusnya sebelum aktivasi.');
  var oldProfile = readFirestoreDocument_(projectId, apiKey, oauthToken, 'users/' + uid) || {};
  if (oldProfile.wargaId && String(oldProfile.wargaId) !== wargaId) {
    throw new Error('Akun Firebase untuk NIK ini sudah tertaut ke data Sensus lain.');
  }
  if (oldProfile.nik && String(oldProfile.nik).replace(/\D/g, '') !== nik) {
    throw new Error('NIK pada profil akun Firebase lama tidak cocok.');
  }
  var update = UrlFetchApp.fetch(authBase + ':update', {
    method: 'post', contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + oauthToken },
    payload: JSON.stringify({ localId: uid, password: dob }), muteHttpExceptions: true
  });
  if (update.getResponseCode() !== 200) {
    throw new Error('Password sementara akun lama gagal disetel: ' + update.getContentText());
  }
  var oldRoles = Array.isArray(oldProfile.roles) && oldProfile.roles.length
    ? oldProfile.roles.map(function(r) { return String(r).toLowerCase(); })
    : [String(oldProfile.role || 'warga').toLowerCase()];
  if (oldRoles.indexOf('warga') < 0) oldRoles.push('warga');
  var profile = {
    uid: uid, email: email, nik: nik, nama: String(resident.nama || oldProfile.nama || ''),
    wargaId: wargaId, role: String(oldProfile.role || 'warga'), roles: oldRoles,
    telepon: String(resident.telepon || oldProfile.telepon || ''),
    alamat: String(resident.alamat || oldProfile.alamat || ''),
    rt: String(resident.rt || oldProfile.rt || ''), rw: String(resident.rw || oldProfile.rw || ''),
    kawil: String(resident.kawil || oldProfile.kawil || ''),
    rtId: String(resident.rtId || oldProfile.rtId || ''),
    rwId: String(resident.rwId || oldProfile.rwId || ''),
    kawilId: String(resident.kawilId || oldProfile.kawilId || ''),
    status: oldProfile.status || 'Aktif', mustChangePassword: true,
    passwordResetAt: { __firestoreTimestamp: new Date().toISOString() },
    passwordResetBy: actorUid, updatedAt: { __firestoreTimestamp: new Date().toISOString() }
  };
  firestorePatchDocument_(projectId, apiKey, oauthToken, 'users/' + uid, profile);
  return { ok: true, uid: uid, emailAlias: email, message: 'Akun Firebase lama berhasil ditautkan kembali.' };
}

function rejectResidentAccount_(data, actorUid, actorProfile, actorToken, apiKey, projectId) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) throw new Error('Permintaan akun sedang diproses petugas lain. Coba kembali.');
  try {
  var requestId = String(data.requestId || '').trim();
  var reason = String(data.alasan || '').trim();
  if (!requestId) throw new Error('ID permintaan tidak valid.');
  if (reason.length < 5) throw new Error('Alasan penolakan wajib diisi minimal 5 karakter.');
  var requestPath = 'kampung/kiarajangkung/permintaan_akun/' + requestId;
  var request = readFirestoreDocument_(projectId, apiKey, actorToken, requestPath);
  if (!request) throw new Error('Permintaan akun tidak ditemukan.');
  var approverRole = verifyAccountRequestApprover_(actorProfile, request);
  if (String(request.status || '') !== 'menunggu') throw new Error('Permintaan ini sudah diproses.');
  var stamp = { __firestoreTimestamp: new Date().toISOString() };
  var wargaId = String(request.wargaId || '');
  var auditId = Utilities.getUuid();
  var oauthToken = ScriptApp.getOAuthToken();
  var writes = [
    firestoreUpdateWrite_(projectId, requestPath, {
      status: 'ditolak', alasanPenolakan: reason, diprosesOlehUid: actorUid,
      diprosesOlehRole: approverRole, diprosesPada: stamp, updatedAt: stamp
    }),
    firestoreUpdateWrite_(projectId, 'kampung/kiarajangkung/permintaan_akun_index/' + wargaId, {
      requestId: requestId, status: 'ditolak', updatedAt: stamp
    }),
    firestoreUpdateWrite_(projectId, 'kampung/kiarajangkung/riwayat_akun/' + auditId, {
      aksi: 'pendaftaran_ditolak', wargaId: wargaId, requestId: requestId,
      alasan: reason, olehUid: actorUid, olehRole: approverRole, waktu: stamp
    })
  ];
  commitFirestoreWrites_(projectId, apiKey, oauthToken, writes);
  return { ok: true, message: 'Permintaan pendaftaran ditolak dan alasannya dicatat.' };
  } finally {
    lock.releaseLock();
  }
}

function listFirestoreDocuments_(projectId, apiKey, token, collectionPath) {
  var result = [];
  var pageToken = '';
  do {
    var url = 'https://firestore.googleapis.com/v1/projects/' + encodeURIComponent(projectId) +
      '/databases/(default)/documents/' + collectionPath.split('/').map(encodeURIComponent).join('/') +
      '?pageSize=1000&key=' + encodeURIComponent(apiKey) + (pageToken ? '&pageToken=' + encodeURIComponent(pageToken) : '');
    var response = UrlFetchApp.fetch(url, { method: 'get', headers: { Authorization: 'Bearer ' + token }, muteHttpExceptions: true });
    if (response.getResponseCode() !== 200) throw new Error('Gagal membaca daftar akun pengelola.');
    var body = JSON.parse(response.getContentText() || '{}');
    (body.documents || []).forEach(function(raw) {
      var fields = {};
      Object.keys(raw.fields || {}).forEach(function(k) { fields[k] = decodeFirestoreValue_(raw.fields[k]); });
      var nameParts = String(raw.name || '').split('/');
      result.push({ id: nameParts[nameParts.length - 1], data: fields });
    });
    pageToken = body.nextPageToken || '';
  } while (pageToken && result.length < 5000);
  return result;
}

function notifyAccountApprovers_(projectId, apiKey, token, requestId, request) {
  var users = listFirestoreDocuments_(projectId, apiKey, token, 'users');
  var targets = [];
  users.forEach(function(user) {
    var roles = accountRequestRoleSet_(user.data);
    var isAdmin = roles.indexOf('admin') >= 0;
    var isRt = roles.indexOf('ketua_rt') >= 0 && String(user.data.rtId || '') &&
      String(user.data.rtId || '') === String(request.rtId || '');
    if ((isAdmin || isRt) && String(user.data.status || '').toLowerCase() === 'aktif') targets.push(user.id);
  });
  var stamp = { __firestoreTimestamp: new Date().toISOString() };
  targets.forEach(function(uid) {
    var notificationId = 'akun_' + requestId.replace(/[^a-zA-Z0-9_-]/g, '_');
    firestorePatchDocument_(projectId, apiKey, token,
      'users/' + uid + '/notifikasi/' + notificationId, {
        kategori: 'akun', jenis: 'permintaan_akun', judul: 'Permintaan akun warga',
        pesan: String(request.nama || 'Warga') + ' mengajukan pembuatan akun. Periksa wilayah dan data Sensus.',
        referensiJenis: 'permintaan_akun', referensiId: requestId,
        isRead: false, createdAt: stamp
      });
  });
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}