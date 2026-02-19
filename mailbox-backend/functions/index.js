const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

/**
 * Generic notification sender for a user.
 *
 * Request body (JSON):
 * {
 *   userId: string,               // required
 *   type?: "mail" | "dryer",      // optional, defaults to "mail"
 *   event?: "started"|"finished", // optional, for dryer
 *   title?: string,               // optional, default based on type/event
 *   body?: string                 // optional, default based on type/event
 * }
 */
exports.sendMailNotification = functions.https.onRequest(async (req, res) => {
  try {
    // 1) Basic validation
    if (req.method !== 'POST') {
      return res.status(405).send('Method Not Allowed');
    }

    if (!req.is('application/json')) {
      return res.status(400).send('Content-Type must be application/json');
    }

    const body = req.body || {};
    const userId = body.userId;
    const type = body.type;
    const event = body.event;
    const customTitle = body.title;
    const customBody = body.body;

    if (!userId) {
      return res.status(400).send('Missing userId');
    }

    // Default type is "mail" to keep old callers working
    const notifType = type || 'mail';

    console.log('✅ sendMailNotification for user:', userId, {
      notifType,
      event,
    });

    const userRef = db.collection('users').doc(userId);

    // 2) Update Firestore flags based on type so SwiftUI can react
    if (notifType === 'mail') {
      await userRef.set(
        {
          mailDetected: true,
          mailLastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    } else if (notifType === 'dryer') {
      await userRef.set(
        {
          dryerRunning: event === 'started',
          dryerLastEvent: event || null,
          dryerLastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    // 3) Find active devices + tokens
    const snap = await userRef
      .collection('devices')
      .where('isActive', '==', true)
      .get();

    const tokens = [];
    snap.forEach((d) => {
      const data = d.data();
      if (data && data.token) {
        tokens.push(data.token);
      }
    });

    if (!tokens.length) {
      console.log('⚠️ No tokens found for user:', userId);
      // We'll still log a notification in Firestore below.
    }

    // 4) Determine final title/body
    let finalTitle;
    let finalBody;

    if (customTitle) {
      finalTitle = customTitle;
    } else if (notifType === 'dryer') {
      finalTitle = 'Dryer Notifier';
    } else {
      finalTitle = '📬 You\'ve got mail!';
    }

    if (customBody) {
      finalBody = customBody;
    } else if (notifType === 'dryer') {
      if (event === 'started') {
        finalBody = 'Your dryer is on — phone is listening.';
      } else {
        finalBody = 'Your clothes are done. Dryer has stopped.';
      }
    } else {
      finalBody = 'Mail was just detected in your mailbox.';
    }

    // 5) Build FCM message and send (if we have any tokens)
    let resp = {successCount: 0, failureCount: 0, responses: []};
    let details = [];

    if (tokens.length > 0) {
      const message = {
        notification: {
          title: finalTitle,
          body: finalBody,
        },
        apns: {
          headers: {'apns-priority': '10'},
          payload: {aps: {sound: 'default'}},
        },
        tokens,
      };

      resp = await admin.messaging().sendEachForMulticast(message);

      details = resp.responses.map((r, i) => {
        const err = r.error || {};
        return {
          token: tokens[i],
          success: r.success,
          errorCode: err.code || null,
          errorMsg: err.message || null,
        };
      });

      console.log('📨 Push result:', JSON.stringify(details, null, 2));
    }

    // 6) Log into /notifications so NotificationsView can show history
    await userRef.collection('notifications').add({
      title: finalTitle,
      body: finalBody,
      type: notifType,
      event: event || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 7) Respond to caller
    return res.status(200).json({
      successCount: resp.successCount,
      failureCount: resp.failureCount,
      details,
    });
  } catch (error) {
    console.error('🔥 sendMailNotification error:', error);

    const code = error && error.code ? error.code : null;
    const message =
      (error && error.message ? error.message : null) || String(error);

    return res.status(500).json({
      code,
      message,
    });
  }
});
